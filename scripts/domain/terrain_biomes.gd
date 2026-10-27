extends RefCounted
## Owns climate classification, hydrology-aware habitats and canopy suitability.
const VERSION := 1
const Climate = preload("res://scripts/domain/terrain_climate.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const NAMES: Array[String] = ["Marine", "Ice", "Tundra", "Cold desert", "Hot desert", "Steppe", "Grassland", "Savanna", "Boreal forest", "Temperate forest", "Temperate rainforest", "Tropical rainforest", "Lake water", "Wetland", "Riparian woodland"]
const COLORS: Array[Color] = [Color("285b70"), Color("e4edf0"), Color("9b9980"), Color("b0a28a"), Color("d8b772"), Color("b6a369"), Color("8f9c58"), Color("a8a35b"), Color("486b5a"), Color("4d7947"), Color("306854"), Color("245d36"), Color("397f98"), Color("668568"), Color("4b8055")]
var ids := PackedByteArray()
var size := Vector2i.ZERO
const PALETTE_SIZE := Vector2i(281, 601) # 0.5°C by 10 mm/year.
static var _palette: Image
var image: Image
var generation_ms: float = 0.0
var canopy := PackedFloat32Array()
var water_support := PackedFloat32Array()
var effective_rainfall := PackedFloat32Array()
var habitat_field: Image
var biome_field: Image
var _queue: Array = []


static func habitat(temperature: float, rainfall: float, support: float, slope: float, water: int = -1, height: float = 20.0) -> Dictionary:
	var effective: float = rainfall + support * Climate.evaporative_demand(temperature) * 1.2
	var id: int = classify(temperature, effective)
	if water >= 0:
		id = water
	elif temperature >= 2.0:
		if slope < 0.065 and (support > 0.45 or (rainfall > 2200.0 and slope < 0.025 and height < 45.0)):
			id = 13
		elif support > 0.35 and slope < 0.35:
			id = 14
	var density: float = [0.0, 0.0, 0.0, 0.0, 0.0, 0.02, 0.05, 0.18, 0.7, 0.8, 0.9, 0.95, 0.0, 0.25, 0.7][id]
	density *= (1.0 - smoothstep(0.25, 0.65, slope)) * smoothstep(1.0, 5.0, temperature)
	return {"biome_id": id, "canopy": density, "effective_rainfall": effective}


func native_cell_info(cell: int) -> Dictionary:
	return {"biome_id": int(ids[cell]), "biome": NAMES[ids[cell]], "canopy": canopy[cell],
		"water_support": water_support[cell], "effective_rainfall": effective_rainfall[cell]}



func support_at(uv: Vector2) -> float:
	if habitat_field == null:
		return 0.0
	var point: Vector2 = uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(habitat_field.get_size() - Vector2i.ONE)
	var x: int = floori(point.x)
	var y: int = floori(point.y)
	var right: int = mini(x + 1, habitat_field.get_width() - 1)
	var bottom: int = mini(y + 1, habitat_field.get_height() - 1)
	return lerpf(lerpf(habitat_field.get_pixel(x, y).r, habitat_field.get_pixel(right, y).r, point.x - x), lerpf(habitat_field.get_pixel(x, bottom).r, habitat_field.get_pixel(right, bottom).r, point.x - x), point.y - y)


static func moisture_ratio(temperature: float, rainfall: float) -> float:
	# Annual evaporative-demand proxy in mm, not a hydrological PET solution.
	return rainfall / Climate.evaporative_demand(temperature)


static func classify(temperature: float, rainfall: float, land: bool = true) -> int:
	if not land:
		return 0
	if temperature < -12.0:
		return 1
	if temperature < 2.0:
		return 2
	var moisture: float = moisture_ratio(temperature, rainfall)
	if rainfall < 150.0 or moisture < 0.20:
		return 4 if temperature >= 18.0 else 3
	if moisture < 0.45:
		return 5
	if temperature >= 20.0:
		return 11 if rainfall >= 1800.0 else 7
	if temperature < 8.0:
		return 8 if moisture >= 0.75 else 6
	if rainfall >= 2000.0:
		return 10
	return 9 if moisture >= 0.85 else 6


func generate(climate: RefCounted, geography: RefCounted, graph: RefCounted = null, hydrology: RefCounted = null) -> void:
	var started: int = Time.get_ticks_usec()
	image = palette_image()
	size = climate.size
	if graph == null or hydrology == null or not hydrology.error.is_empty():
		ids.resize(size.x * size.y)
		for y in range(size.y):
			for x in range(size.x):
				var i: int = y * size.x + x
				var height: float = Grid.sample(geography.display_heights, geography.contour_size, Vector2(x, y) / Vector2(size - Vector2i.ONE))
				ids[i] = classify(climate.temperature[i], climate.rainfall[i], height >= 0.2)
		generation_ms = (Time.get_ticks_usec() - started) / 1000.0
		return
	ids.resize(graph.count)
	canopy.resize(graph.count)
	water_support.resize(graph.count)
	effective_rainfall.resize(graph.count)
	var distances := PackedFloat64Array()
	var levels := PackedFloat64Array()
	distances.resize(graph.count)
	distances.fill(INF)
	levels.resize(graph.count)
	_queue.clear()
	var radius: float = maxf(maxf(graph.map_size.x, graph.map_size.y) * 0.005, graph.spacing * 1.5)
	for i in range(graph.count):
		var lake: int = hydrology.lake_ids[i]
		if hydrology.ocean[i] == 0 and ((lake >= 0 and hydrology.lakes[lake].active) or hydrology.river_ids[i] >= 0):
			distances[i] = 0.0
			levels[i] = hydrology.lakes[lake].level if lake >= 0 and hydrology.lakes[lake].active else hydrology.bed[i]
			_push([0.0, i])
	while not _queue.is_empty():
		var item: Array = _pop()
		var cell: int = item[1]
		if item[0] > distances[cell] or item[0] > radius * 3.0:
			continue
		for neighbor in graph.neighbors[cell]:
			if hydrology.ocean[neighbor] != 0:
				continue
			var distance: float = distances[cell] + graph.points[cell].distance_to(graph.points[neighbor])
			if distance < distances[neighbor] and distance <= radius * 3.0:
				distances[neighbor] = distance
				levels[neighbor] = levels[cell]
				_push([distance, neighbor])
	for i in range(graph.count):
		var data: Dictionary = climate.cell_info(graph.points[i] / graph.map_size)
		var slope: float = 0.0
		for neighbor in graph.neighbors[i]:
			var length: float = graph.points[i].distance_to(graph.points[neighbor])
			slope = maxf(slope, absf(hydrology.bed[i] - hydrology.bed[neighbor]) * maxf(graph.map_size.x, graph.map_size.y) / 1600.0 / maxf(length, 0.001))
		var support: float = exp(-distances[i] / radius) * exp(-maxf(0.0, hydrology.bed[i] - levels[i]) / 3.0)
		var water: int = 0 if hydrology.ocean[i] != 0 else -1
		var lake: int = hydrology.lake_ids[i]
		if lake >= 0 and hydrology.lakes[lake].active:
			water = 12
		var result: Dictionary = habitat(data.temperature, data.rainfall, support, slope, water, hydrology.bed[i])
		ids[i] = result.biome_id
		canopy[i] = 0.0 if hydrology.river_ids[i] >= 0 else result.canopy
		water_support[i] = support
		effective_rainfall[i] = result.effective_rainfall
	# Only local water effects are spatially filtered; the base climate palette stays continuous.
	size = Grid.sample_size_for(graph.map_size, 256)
	habitat_field = Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
	biome_field = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var uv: Vector2 = Vector2(x, y) / Vector2(size - Vector2i.ONE)
			var cell: int = graph.nearest_cell(uv * graph.map_size)
			habitat_field.set_pixel(x, y, Color(water_support[cell], 1.0 if ids[cell] == 13 else 0.0, 1.0 if ids[cell] == 14 else 0.0, canopy[cell]))
			biome_field.set_pixel(x, y, COLORS[ids[cell]])
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0


func _push(item: Array) -> void:
	_queue.append(item)
	var i: int = _queue.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if _queue[parent][0] <= item[0]:
			break
		_queue[i] = _queue[parent]
		i = parent
	_queue[i] = item


func _pop() -> Array:
	var first: Array = _queue[0]
	var last: Array = _queue.pop_back()
	if not _queue.is_empty():
		var i: int = 0
		while i * 2 + 1 < _queue.size():
			var child: int = i * 2 + 1
			if child + 1 < _queue.size() and _queue[child + 1][0] < _queue[child][0]:
				child += 1
			if last[0] <= _queue[child][0]:
				break
			_queue[i] = _queue[child]
			i = child
		_queue[i] = last
	return first


static func cell_info(temperature: float, rainfall: float, land: bool) -> Dictionary:
	var id: int = classify(temperature, rainfall, land)
	return {"biome_id": id, "biome": NAMES[id], "moisture_ratio": moisture_ratio(temperature, rainfall)}


static func palette_image() -> Image:
	if _palette != null:
		return _palette
	_palette = Image.create(PALETTE_SIZE.x, PALETTE_SIZE.y, false, Image.FORMAT_RGBA8)
	for y in range(PALETTE_SIZE.y):
		for x in range(PALETTE_SIZE.x):
			var temperature: float = -80.0 + x * 0.5
			var rainfall: float = y * 10.0
			_palette.set_pixel(x, y, COLORS[classify(temperature, rainfall, true)])
	_palette = _soften_palette(_palette)
	return _palette


static func _soften_palette(source: Image) -> Image:
	var weights: Array[float] = [1.0, 4.0, 6.0, 4.0, 1.0]
	for axis in range(2):
		var target := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				var color := Color(0, 0, 0, 0)
				for tap in range(-2, 3):
					var sx: int = clampi(x + (tap if axis == 0 else 0), 0, source.get_width() - 1)
					var sy: int = clampi(y + (tap if axis == 1 else 0), 0, source.get_height() - 1)
					color += source.get_pixel(sx, sy) * weights[tap + 2] / 16.0
				target.set_pixel(x, y, color)
		source = target
	return source
