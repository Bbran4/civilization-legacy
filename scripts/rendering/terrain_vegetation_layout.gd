extends RefCounted
## Owns deterministic decorative tree placement; ecology remains owned by Biomes.
const Alea = preload("res://scripts/domain/alea.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const MAX_INSTANCES := 60000
const CANDIDATE_TARGET := 100000.0
var instances: Array[Dictionary] = []
var counts := PackedInt32Array()
var generation_ms: float = 0
var candidate_count: int = 0
var spacing: float = 2.0
var _fields: Array[PackedFloat32Array] = []
var _sizes: Array[Vector2i] = []
var _occupied: Dictionary = {}

static func species(biome: int) -> int:
	match biome:
		8: return 1
		3, 4, 5, 7: return 2
		11: return 3
		13: return 4
		_: return 0

func _ground(point: Vector2, extent: Vector2, radius: float) -> Vector2:
	var uv: Vector2 = point / extent
	var minimum: float = INF
	for i in range(_fields.size()):
		minimum = minf(minimum, Grid.sample(_fields[i], _sizes[i], uv))
	var field: PackedFloat32Array = _fields[-1]
	var size: Vector2i = _sizes[-1]
	var l: float = Grid.sample(field, size, (point - Vector2(radius, 0)) / extent)
	var r: float = Grid.sample(field, size, (point + Vector2(radius, 0)) / extent)
	var t: float = Grid.sample(field, size, (point - Vector2(0, radius)) / extent)
	var b: float = Grid.sample(field, size, (point + Vector2(0, radius)) / extent)
	minimum = minf(minimum, minf(minf(l, r), minf(t, b)))
	var slope: float = Vector2(r - l, b - t).length() / (radius * 2)
	return Vector2(minimum, slope)

func _clear_space(point: Vector2) -> bool:
	var key := Vector2i(point.floor())
	for y in range(key.y - 1, key.y + 2):
		for x in range(key.x - 1, key.x + 2):
			for other in _occupied.get(Vector2i(x, y), []):
				if point.distance_squared_to(other) < 0.36:
					return false
	return true

func generate(terrain: Node) -> void:
	var started: int = Time.get_ticks_usec()
	instances.clear()
	_occupied.clear()
	_fields.clear()
	_sizes.clear()
	candidate_count = 0
	var graph = terrain.graph
	if graph == null or terrain.biomes == null or terrain.biomes.canopy.size() != graph.count or terrain.hydrology == null or not terrain.hydrology.error.is_empty():
		counts.clear()
		return
	counts.resize(graph.count)
	counts.fill(0)
	if terrain.detail != null and terrain.detail.active:
		_fields.assign(terrain.detail.height_fields)
		_sizes.assign(terrain.detail.height_sizes)
	else:
		var field: PackedFloat32Array = terrain.height_samples.duplicate()
		for i in range(field.size()):
			field[i] *= terrain.relief_scale()
		_fields.append(field)
		_sizes.append(terrain.sample_size())
	spacing = maxf(2.0, sqrt(graph.map_size.x * graph.map_size.y / CANDIDATE_TARGET))
	var noise := FastNoiseLite.new()
	noise.seed = int(terrain.map_seed.hash())
	noise.frequency = 0.04
	noise.fractal_octaves = 2
	var sea: float = terrain.sea_level * terrain.relief_scale()
	for cell in range(graph.count):
		var density: float = terrain.biomes.canopy[cell]
		if density <= 0 or terrain.hydrology.ocean[cell] != 0 or terrain.hydrology.river_ids[cell] >= 0:
			continue
		var lake: int = terrain.hydrology.lake_ids[cell]
		if lake >= 0 and terrain.hydrology.lakes[lake].active:
			continue
		var water_level: float = sea
		for neighbor in graph.neighbors[cell]:
			var id: int = terrain.hydrology.lake_ids[neighbor]
			if id >= 0 and terrain.hydrology.lakes[id].active:
				var level: float = (terrain.height_offset + (terrain.hydrology.lakes[id].level / 100.0 - 0.2) * terrain.elevation) * terrain.relief_scale()
				water_level = maxf(water_level, level)
		var polygon: PackedVector2Array = graph.polygon(cell)
		if polygon.size() < 3:
			continue
		var areas := PackedFloat32Array()
		var total: float = 0
		for i in range(1, polygon.size() - 1):
			total += absf((polygon[i] - polygon[0]).cross(polygon[i + 1] - polygon[0])) * 0.5
			areas.append(total)
		if total <= 0:
			continue
		var expected: float = total / (spacing * spacing)
		var candidates: int = mini(64, ceili(expected))
		var random = Alea.new(terrain.map_seed + ":vegetation:" + str(cell))
		for candidate in range(candidates):
			candidate_count += 1
			var triangle: int = 0
			var pick: float = random.next() * total
			while triangle + 1 < areas.size() and pick > areas[triangle]:
				triangle += 1
			var u: float = sqrt(random.next())
			var v: float = random.next()
			var point: Vector2 = polygon[0] * (1 - u) + polygon[triangle + 1] * (u * (1 - v)) + polygon[triangle + 2] * (u * v)
			var rank: float = random.next()
			var scale: float = lerpf(0.8, 1.2, random.next())
			var rotation: float = random.next() * TAU
			var tint: float = lerpf(0.88, 1.12, random.next())
			var priority: float = random.next()
			var cluster: float = smoothstep(-0.4, 0.25, noise.get_noise_2d(point.x, point.y))
			if rank > density * cluster * minf(1, expected / candidates) or not _clear_space(point):
				continue
			var radius: float = 0.43 * scale
			if point.x < radius or point.y < radius or point.x > graph.map_size.x - radius or point.y > graph.map_size.y - radius:
				continue
			var ground: Vector2 = _ground(point, graph.map_size, radius)
			if ground.x <= water_level + 0.04 or ground.y > 0.85:
				continue
			if terrain.hydrology_view != null and terrain.hydrology_view.river_near(point, radius):
				continue
			var height: float = Grid.sample(_fields[-1], _sizes[-1], point / graph.map_size)
			instances.append({"point": point, "height": height, "cell": cell, "kind": species(terrain.biomes.ids[cell]), "scale": scale, "rotation": rotation, "tint": tint, "priority": priority})
			var bucket := Vector2i(point.floor())
			if not _occupied.has(bucket):
				_occupied[bucket] = []
			_occupied[bucket].append(point)
	if instances.size() > MAX_INSTANCES:
		instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.priority < b.priority)
		instances.resize(MAX_INSTANCES)
	for tree in instances:
		counts[tree.cell] += 1
	_occupied.clear()
	_fields.clear()
	_sizes.clear()
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0
