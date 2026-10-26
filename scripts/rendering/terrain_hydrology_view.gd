extends Node3D
## Fixed lake surfaces and runoff-sized river ribbons, rebuilt on source/climate edits.
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const WATER_SHADER = preload("res://scripts/rendering/hydrology.gdshader")
var lakes_mesh: MeshInstance3D
var rivers_mesh: MeshInstance3D
var _terrain: Node
var _heights_view: bool = false
var _mode: int = 0
var build_count: int = 0
var river_corridors: Array[Dictionary] = []
var _river_buckets: Dictionary = {}
var _bucket_size: float = 1.0


func clear() -> void:
	river_corridors.clear()
	_river_buckets.clear()
	for mesh in [lakes_mesh, rivers_mesh]:
		if is_instance_valid(mesh):
			mesh.free()
	lakes_mesh = null
	rivers_mesh = null


func build(terrain: Node) -> void:
	clear()
	_terrain = terrain
	build_count += 1
	var hydro = terrain.hydrology
	if hydro == null or not hydro.error.is_empty() or not terrain.show_water or not is_equal_approx(terrain.sea_level, terrain.height_offset):
		return
	_build_lakes(terrain.graph, hydro)
	_build_rivers(terrain.graph, hydro)
	_update_visibility()


func _world_height(level: float) -> float:
	return (_terrain.height_offset + (level / 100.0 - 0.2) * _terrain.elevation) * _terrain.relief_scale()


func _surface(point: Vector2) -> float:
	var uv: Vector2 = point / _terrain.map_size
	if _terrain.detail != null and _terrain.detail.active:
		return Grid.sample(_terrain.detail.field_heights, _terrain.detail.field_size, uv)
	return _terrain.base_surface_height(uv)


func _water_node(name_text: String, vertices: PackedVector3Array, indices: PackedInt32Array, colours: PackedColorArray, colour: Color, priority: int) -> MeshInstance3D:
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.render_priority = priority
	material.set_shader_parameter("water_colour", colour)
	var node := MeshInstance3D.new()
	node.name = name_text
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	return node


func _build_lakes(graph: RefCounted, hydro: RefCounted) -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var colours := PackedColorArray()
	for triangle in range(0, graph.triangles.size(), 3):
		var cells: Array[int] = [graph.triangles[triangle], graph.triangles[triangle + 1], graph.triangles[triangle + 2]]
		if cells[0] >= graph.count or cells[1] >= graph.count or cells[2] >= graph.count:
			continue
		var candidates: Array[int] = []
		for cell in cells:
			var lake_id: int = hydro.lake_ids[cell]
			if lake_id >= 0 and hydro.lakes[lake_id].active and lake_id not in candidates:
				candidates.append(lake_id)
		for lake_id in candidates:
			var level: float = hydro.lakes[lake_id].level
			var polygon: Array[Vector3] = []
			for cell in cells:
				var point: Vector2 = graph.points[cell]
				polygon.append(Vector3(point.x, hydro.bed[cell], point.y))
			var clipped: Array[Vector3] = []
			for edge in range(3):
				var a: Vector3 = polygon[edge]
				var b: Vector3 = polygon[(edge + 1) % 3]
				if a.y < level:
					clipped.append(a)
				if (a.y < level) != (b.y < level):
					clipped.append(a.lerp(b, (level - a.y) / (b.y - a.y)))
			if clipped.size() < 3:
				continue
			var offset: int = vertices.size()
			for point in clipped:
				vertices.append(Vector3(point.x - graph.map_size.x * 0.5, _world_height(level) + 0.015 * _terrain.relief_scale(), point.z - graph.map_size.y * 0.5))
				colours.append(Color(clampf((level - point.y) / 8.0, 0, 1), 0, 0))
			for corner in range(1, clipped.size() - 1):
				indices.append_array(PackedInt32Array([offset, offset + corner, offset + corner + 1]))
	lakes_mesh = _water_node("LakeSurfaces", vertices, indices, colours, Color("246b8e"), 2)


func _point_height(cell: int, point: Vector2, hydro: RefCounted) -> float:
	if hydro.ocean[cell]:
		return _world_height(20.0)
	if hydro.lake_ids[cell] >= 0 and hydro.lakes[hydro.lake_ids[cell]].active:
		return _world_height(hydro.lakes[hydro.lake_ids[cell]].level)
	return _surface(point)


func _width(cell: int, hydro: RefCounted) -> float:
	var discharge: float = hydro.flow[cell]
	if hydro.lake_ids[cell] >= 0:
		discharge = hydro.lakes[hydro.lake_ids[cell]].outflow
	var longest: float = maxf(_terrain.map_size.x, _terrain.map_size.y)
	return clampf(longest * 0.00035 * pow(maxf(1.0, discharge / hydro.river_threshold), 0.35), longest * 0.00035, longest * 0.0015)


func _build_rivers(graph: RefCounted, hydro: RefCounted) -> void:
	_bucket_size = maxf(1.0, graph.spacing * 2.0)
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var lift: float = 0.04 * _terrain.relief_scale()
	for river in hydro.rivers:
		var points := PackedVector3Array()
		var widths := PackedFloat32Array()
		for segment in range(river.cells.size() - 1):
			var from: int = river.cells[segment]
			var to: int = river.cells[segment + 1]
			var a: Vector2 = graph.points[from]
			var b: Vector2 = graph.points[to]
			var from_width: float = _width(from, hydro)
			var to_width: float = from_width if hydro.lake_ids[to] >= 0 or hydro.ocean[to] else _width(to, hydro)
			var steps: int = clampi(ceili(a.distance_to(b) / maxf(0.1, graph.spacing * 0.35)), 1, 16)
			for step in range(steps + (1 if segment == river.cells.size() - 2 else 0)):
				var t: float = float(step) / steps
				var point: Vector2 = a.lerp(b, t)
				var height: float = _surface(point)
				if step == 0:
					height = _point_height(from, point, hydro)
				elif step == steps:
					height = _point_height(to, point, hydro)
				points.append(Vector3(point.x - graph.map_size.x * 0.5, height + lift, point.y - graph.map_size.y * 0.5))
				widths.append(lerpf(from_width, to_width, t))
		var rounded: Dictionary = _round_river(points, widths, graph, hydro, lift)
		points = rounded.points
		widths = rounded.widths
		for i in range(points.size() - 1):
			var a: Vector2 = Vector2(points[i].x, points[i].z) + graph.map_size * 0.5
			var b: Vector2 = Vector2(points[i + 1].x, points[i + 1].z) + graph.map_size * 0.5
			var radius: float = maxf(widths[i], widths[i + 1]) * 0.5
			var id: int = river_corridors.size()
			river_corridors.append({"a": a, "b": b, "radius": radius})
			var low := Vector2i(((a.min(b) - Vector2.ONE * radius) / _bucket_size).floor())
			var high := Vector2i(((a.max(b) + Vector2.ONE * radius) / _bucket_size).floor())
			for y in range(low.y, high.y + 1):
				for x in range(low.x, high.x + 1):
					var key := Vector2i(x, y)
					if not _river_buckets.has(key):
						_river_buckets[key] = []
					_river_buckets[key].append(id)
		var offset: int = vertices.size()
		for i in range(points.size()):
			var tangent: Vector3 = points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]
			var side := Vector3(-tangent.z, 0, tangent.x).normalized() * widths[i] * 0.5
			vertices.append(points[i] - side)
			vertices.append(points[i] + side)
			colours.append_array(PackedColorArray([Color(0.15, 0, 0), Color(0.15, 0, 0)]))
			if i > 0:
				var j: int = offset + i * 2
				indices.append_array(PackedInt32Array([j - 2, j - 1, j, j - 1, j + 1, j]))
	rivers_mesh = _water_node("RiverRibbons", vertices, indices, colours, Color("4292b6"), 3)


func _round_river(points: PackedVector3Array, widths: PackedFloat32Array, graph: RefCounted, hydro: RefCounted, lift: float) -> Dictionary:
	# Round only visual bends. Keep source/mouth locations and graph routing exact.
	for iteration in range(2):
		var rounded := PackedVector3Array([points[0]])
		var rounded_widths := PackedFloat32Array([widths[0]])
		for i in range(points.size() - 1):
			for t in [0.25, 0.75]:
				var point: Vector3 = points[i].lerp(points[i + 1], t)
				var xz: Vector2 = Vector2(point.x, point.z) + graph.map_size * 0.5
				var cell: int = graph.nearest_cell(xz)
				point.y = maxf(_surface(xz), _point_height(cell, xz, hydro)) + lift
				rounded.append(point)
				rounded_widths.append(lerpf(widths[i], widths[i + 1], t))
		rounded.append(points[points.size() - 1])
		rounded_widths.append(widths[widths.size() - 1])
		points = rounded
		widths = rounded_widths
	return {"points": points, "widths": widths}


func set_view(mode: int, heights: bool) -> void:
	_mode = mode
	_heights_view = heights
	_update_visibility()


func _update_visibility() -> void:
	visible = not _heights_view and _mode == 0


func river_near(point: Vector2, clearance: float = 0.0) -> bool:
	var cell := Vector2i((point / _bucket_size).floor())
	var reach: int = ceili(clearance / _bucket_size) + 1
	for y in range(cell.y - reach, cell.y + reach + 1):
		for x in range(cell.x - reach, cell.x + reach + 1):
			for id in _river_buckets.get(Vector2i(x, y), []):
				var segment: Dictionary = river_corridors[id]
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, segment.a, segment.b)
				if point.distance_to(closest) <= segment.radius + clearance:
					return true
	return false
