extends Node3D
## Three prebuilt meshes per chunk, sampled from one fixed high-resolution field.
## Orthographic projection gives all visible chunks the same screen-space scale.

const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const Alea = preload("res://scripts/domain/alea.gd")
var active: bool = false
var chunks: Array[Dictionary] = []
var chunk_count := Vector2i.ZERO
var high_cells: int = 128
var build_ms: float = 0.0
var build_count: int = 0
var bounds := Vector2.ZERO
var field_heights := PackedFloat32Array()
var field_size := Vector2i.ZERO
var target_level: int = 0
var displayed_detail: float = 0.0
var current_level: int = 0
var blend: float = 1.0
var _terrain: Node
var _material: ShaderMaterial


func _ready() -> void:
	_terrain = get_parent()


func reset() -> void:
	active = false
	for chunk in chunks:
		chunk.node.free()
	chunks.clear()
	field_heights.clear()
	field_size = Vector2i.ZERO
	if is_instance_valid(_terrain):
		var surface := _terrain.get_node_or_null("Surface") as MeshInstance3D
		if surface != null:
			surface.visible = true
	_material = null


func build() -> void:
	reset()
	if not _terrain.close_detail_enabled or _terrain.graph == null:
		return
	var started: int = Time.get_ticks_usec()
	high_cells = clampi(ceili(_terrain.close_detail_resolution / 8.0) * 8, 32, 256)
	var longest: float = maxf(_terrain.map_size.x, _terrain.map_size.y)
	var axis_chunks: int = clampi(ceili(longest / 256.0), 1, 8)
	chunk_count = Vector2i(maxi(1, roundi(_terrain.map_size.x / longest * axis_chunks)), maxi(1, roundi(_terrain.map_size.y / longest * axis_chunks)))
	var source_size := chunk_count * high_cells + Vector2i.ONE
	var source: PackedFloat32Array = _terrain.graph.rasterize(source_size, _terrain.surface_smoothing)
	var random = Alea.new(_terrain.map_seed)
	var noise := FastNoiseLite.new()
	noise.seed = int(random.next() * 2147483647.0)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.65
	noise.fractal_octaves = 3
	var scale: float = _terrain.relief_scale()
	var sea: float = _terrain.sea_level * scale
	bounds = Vector2(INF, -INF)
	for y in range(source_size.y):
		for x in range(source_size.x):
			var i: int = y * source_size.x + x
			var height: float = (_terrain.height_offset + (source[i] - 0.2) * _terrain.elevation) * scale
			var point: Vector2 = (Vector2(x, y) / Vector2(source_size - Vector2i.ONE) - Vector2(0.5, 0.5)) * _terrain.map_size
			source[i] = height + noise.get_noise_2d(point.x, point.y) * _terrain.micro_detail_strength * smoothstep(sea + 0.2, sea + 2.0, height)
			bounds.x = minf(bounds.x, source[i])
			bounds.y = maxf(bounds.y, source[i])
	# Normals belong to the whole field, so chunk edges share lighting as well
	# as positions; one-sided derivatives inside each chunk would leave seams.
	var levels: Array[int] = [high_cells / 4, high_cells / 2, high_cells]
	var level_normals: Array[PackedVector3Array] = []
	for count in levels:
		var size := chunk_count * count + Vector2i.ONE
		var field := PackedFloat32Array()
		field.resize(size.x * size.y)
		var stride: int = high_cells / count
		for row in range(size.y):
			for col in range(size.x):
				field[row * size.x + col] = source[row * stride * source_size.x + col * stride]
		level_normals.append(Grid.normals_from_heights(field, size, _terrain.map_size))
	_material = _terrain._land_material.duplicate()
	_material.set_shader_parameter("terrain_lod", true)
	_material.set_shader_parameter("lod_blend", 1.0)
	for y in range(chunk_count.y):
		for x in range(chunk_count.x):
			var uv_rect := Rect2(Vector2(x, y) / Vector2(chunk_count), Vector2.ONE / Vector2(chunk_count))
			var extent: Vector2 = _terrain.map_size / Vector2(chunk_count)
			var center: Vector2 = (uv_rect.get_center() - Vector2(0.5, 0.5)) * _terrain.map_size
			var meshes: Array[ArrayMesh] = []
			var fields: Array[PackedFloat32Array] = []
			var sizes: Array[Vector2i] = []
			var normals: Array[PackedVector3Array] = []
			for level in range(3):
				var count: int = levels[level]
				var size := Vector2i.ONE * (count + 1)
				var field := PackedFloat32Array()
				field.resize(size.x * size.y)
				var stride: int = high_cells / count
				var global_size := chunk_count * count + Vector2i.ONE
				var shared := PackedVector3Array()
				shared.resize(field.size())
				for row in range(size.y):
					for col in range(size.x):
						field[row * size.x + col] = source[(y * high_cells + row * stride) * source_size.x + x * high_cells + col * stride]
						shared[row * size.x + col] = level_normals[level][(y * count + row) * global_size.x + x * count + col]
				fields.append(field)
				normals.append(shared)
				sizes.append(size)
				var parent: int = maxi(0, fields.size() - 2)
				meshes.append(Grid.mesh_from_heights(field, size, extent, center, uv_rect, fields[parent], sizes[parent], shared, normals[parent]))
			var node := MeshInstance3D.new()
			node.name = "Chunk_%d_%d" % [x, y]
			node.mesh = meshes[0]
			node.material_override = _material
			add_child(node, false, Node.INTERNAL_MODE_BACK)
			chunks.append({"node": node, "meshes": meshes, "fields": fields, "sizes": sizes})
	field_heights = source
	field_size = source_size
	target_level = 0
	displayed_detail = 0.0
	current_level = 0
	blend = 1.0
	active = true
	_terrain.get_node("Surface").visible = false
	build_count += 1
	build_ms = (Time.get_ticks_usec() - started) / 1000.0


func _process(delta: float) -> void:
	if not active or _terrain._dirty:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var span: float = minf(_terrain.map_size.x, _terrain.map_size.y)
	# Separate entry/exit thresholds prevent jitter when hovering at a boundary.
	if target_level == 0 and camera.size < span * 0.55:
		target_level = 1
	if target_level == 1:
		if camera.size > span * 0.65:
			target_level = 0
		elif camera.size < span * 0.13:
			target_level = 2
	if target_level == 2 and camera.size > span * 0.17:
		target_level = 1
	var next: float = move_toward(displayed_detail, float(target_level), delta * 4.0)
	if not is_equal_approx(next, displayed_detail):
		set_detail(next)


func set_detail(value: float) -> void:
	displayed_detail = clampf(value, 0.0, 2.0)
	var level: int = ceili(displayed_detail)
	blend = 1.0 if level == 0 else displayed_detail - (level - 1)
	if level != current_level:
		for chunk in chunks:
			chunk.node.mesh = chunk.meshes[level]
		current_level = level
	_material.set_shader_parameter("lod_blend", blend)


func set_overview_blend(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter("overview_blend", value)


func set_heightmap_view(enabled: bool) -> void:
	if _material != null:
		_material.set_shader_parameter("heightmap_view", enabled)


func contains(uv: Vector2) -> bool:
	return active and uv.x >= 0.0 and uv.y >= 0.0 and uv.x <= 1.0 and uv.y <= 1.0


func height_at(uv: Vector2) -> float:
	var coord := (uv * Vector2(chunk_count)).clamp(Vector2.ZERO, Vector2(chunk_count) - Vector2(0.00001, 0.00001))
	var cell := Vector2i(coord)
	var fraction: Vector2 = coord - Vector2(cell)
	var chunk: Dictionary = chunks[cell.y * chunk_count.x + cell.x]
	var fine: float = Grid.sample(chunk.fields[current_level], chunk.sizes[current_level], fraction)
	if current_level == 0:
		return fine
	var coarse: float = Grid.sample(chunk.fields[current_level - 1], chunk.sizes[current_level - 1], fraction)
	return lerpf(coarse, fine, blend)


func visible_depth_bounds(camera: Camera3D, focus: Vector3) -> Vector2:
	# Orthographic screen coordinates are independent of camera distance. Bound
	# their footprint at both global height extremes, then inspect fixed samples
	# only inside that rectangle. Include a full cell halo for crossing triangles.
	var basis: Basis = _terrain.global_basis.transposed()
	var right: Vector3 = basis * camera.global_basis.x
	var up: Vector3 = basis * camera.global_basis.y
	var depth_axis: Vector3 = basis * camera.global_basis.z
	var center: Vector3 = _terrain.to_local(focus)
	var determinant: float = right.x * up.z - right.z * up.x
	if absf(determinant) < 0.01:
		return Vector2(INF, -INF)
	var viewport: Vector2 = camera.get_viewport().get_visible_rect().size
	var half_width: float = camera.size * viewport.x / maxf(1.0, viewport.y) * 0.5 + absf(camera.h_offset)
	var half_height: float = camera.size * 0.5
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var low_height: float = minf(bounds.x, _terrain.sea_level * _terrain.relief_scale()) if _terrain.show_water else bounds.x
	var high_height: float = maxf(bounds.y, _terrain.sea_level * _terrain.relief_scale()) if _terrain.show_water else bounds.y
	for height in [low_height, high_height]:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var rx: float = sx * half_width - right.y * (height - center.y)
				var uy: float = sy * half_height - up.y * (height - center.y)
				var point := Vector2(center.x + (rx * up.z - right.z * uy) / determinant, center.z + (right.x * uy - rx * up.x) / determinant)
				low = low.min(point)
				high = high.max(point)
	var steps := Vector2(field_size - Vector2i.ONE)
	var start := Vector2i(((low / _terrain.map_size + Vector2(0.5, 0.5)) * steps).floor()) - Vector2i(4, 4)
	var end := Vector2i(((high / _terrain.map_size + Vector2(0.5, 0.5)) * steps).ceil()) + Vector2i(4, 4)
	start = start.max(Vector2i.ZERO)
	end = end.min(field_size - Vector2i.ONE)
	# Far views already need broad coverage; bound CPU work per camera update.
	if end.x < start.x or end.y < start.y or (end.x - start.x + 1) * (end.y - start.y + 1) > 8192:
		return Vector2(INF, -INF)
	var result := Vector2(INF, -INF)
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var xz: Vector2 = (Vector2(x, y) / steps - Vector2(0.5, 0.5)) * _terrain.map_size
			var offset := Vector3(xz.x, field_heights[y * field_size.x + x], xz.y) - center
			var depth: float = offset.dot(depth_axis)
			result.x = minf(result.x, depth)
			result.y = maxf(result.y, depth)
	# Water and intermediate LOD triangles can span fine extrema; include their
	# local coarse parent heights as well as the authoritative finest samples.
	for y in [start.y, end.y]:
		for x in [start.x, end.x]:
			var xz: Vector2 = (Vector2(x, y) / steps - Vector2(0.5, 0.5)) * _terrain.map_size
			var uv: Vector2 = xz / _terrain.map_size + Vector2(0.5, 0.5)
			for height in [height_at(uv), _terrain.sea_level * _terrain.relief_scale()]:
				var depth: float = (Vector3(xz.x, height, xz.y) - center).dot(depth_axis)
				result.x = minf(result.x, depth)
				result.y = maxf(result.y, depth)
	return result


func set_climate_view(mode: int, field: Texture2D, biome_palette: Texture2D = null) -> void:
	if _material != null:
		_material.set_shader_parameter("climate_mode", mode)
		_material.set_shader_parameter("climate_field", field)
		_material.set_shader_parameter("biomes_enabled", biome_palette != null)
		_material.set_shader_parameter("biome_palette", biome_palette)


func set_hydrology_field(field: Texture2D) -> void:
	if _material != null:
		_material.set_shader_parameter("drainage_field", field)
		_material.set_shader_parameter("hydrology_enabled", field != null)


func set_habitat_fields(habitat: Texture2D, biome: Texture2D) -> void:
	if _material != null:
		_material.set_shader_parameter("habitat_field", habitat)
		_material.set_shader_parameter("biome_field", biome)
		_material.set_shader_parameter("habitats_enabled", habitat != null)
