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
var _lake_polygons: Array[Dictionary] = []
var _lake_buckets: Dictionary = {}
var _river_material: ShaderMaterial
var _lod_key := Vector2(-1, -1)


func clear() -> void:
	_lake_polygons.clear()
	_lake_buckets.clear()
	_river_material = null
	_lod_key = Vector2(-1, -1)
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
	_bucket_size = maxf(1.0, terrain.graph.spacing * 2)
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


func _water_node(name_text: String, vertices: PackedVector3Array, indices: PackedInt32Array, colours: PackedColorArray, colour: Color, priority: int, uvs: PackedVector2Array = PackedVector2Array(), data: PackedVector2Array = PackedVector2Array()) -> MeshInstance3D:
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colours
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = data
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
			_index_lake(clipped, _world_height(level))
			var offset: int = vertices.size()
			for point in clipped:
				vertices.append(Vector3(point.x - graph.map_size.x * 0.5, _world_height(level) + 0.005, point.z - graph.map_size.y * 0.5))
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
	var uvs := PackedVector2Array()
	var data := PackedVector2Array()
	var lift: float = clampf(0.012 * _terrain.relief_scale(), 0.002, 0.02)
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
		var spans: Array[Dictionary] = _dry_spans(points, widths)
		for span_index in range(spans.size()):
			var span: Dictionary = spans[span_index]
			var a: Vector3 = span.a
			var b: Vector3 = span.b
			var pa: Vector2 = Vector2(a.x, a.z) + graph.map_size * 0.5
			var pb: Vector2 = Vector2(b.x, b.z) + graph.map_size * 0.5
			var tangent: Vector2 = (pb - pa).normalized()
			var base: int = vertices.size()
			var drop: float = maxf(0, (a.y - b.y) / maxf(0.001, pa.distance_to(pb)))
			var fall: float = smoothstep(0.6, 1.8, drop)
			for endpoint in range(2):
				var center: Vector2 = pa if endpoint == 0 else pb
				var width: float = span.wa if endpoint == 0 else span.wb
				var adjacent: Vector2 = tangent
				if endpoint == 0 and span_index > 0 and (spans[span_index - 1].b as Vector3).distance_squared_to(a) < 0.00000001:
					var delta: Vector3 = spans[span_index - 1].b - spans[span_index - 1].a
					adjacent = Vector2(delta.x, delta.z).normalized()
				if endpoint == 1 and span_index + 1 < spans.size() and (spans[span_index + 1].a as Vector3).distance_squared_to(b) < 0.00000001:
					var delta: Vector3 = spans[span_index + 1].b - spans[span_index + 1].a
					adjacent = Vector2(delta.x, delta.z).normalized()
				var side: Vector2 = Vector2(-tangent.y - adjacent.y, tangent.x + adjacent.x).normalized()
				side /= maxf(0.5, side.dot(Vector2(-tangent.y, tangent.x)))
				for sign_value in [-1.0, 1.0]:
					var bank: Vector2 = _bank_point(center, center + side * width * sign_value * 0.5)
					vertices.append(Vector3(bank.x - graph.map_size.x * 0.5, _surface(bank) + lift, bank.y - graph.map_size.y * 0.5))
					colours.append(Color(0.15, fall, 0, 1))
					uvs.append(Vector2((sign_value + 1) * 0.5, span.distance + (a.distance_to(b) if endpoint == 1 else 0)))
					data.append(Vector2(span.level, 0))
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
			_index_river(pa, pb, maxf(span.wa, span.wb) * 0.5)
	rivers_mesh = _water_node("RiverRibbons", vertices, indices, colours, Color("367d91"), 3, uvs, data)
	if rivers_mesh != null:
		_river_material = rivers_mesh.material_override
		_river_material.set_shader_parameter("river_mode", true)
		_river_material.set_shader_parameter("map_size", _terrain.map_size)
		_river_material.set_shader_parameter("surface_lift", lift)
		if _terrain.detail == null or not _terrain.detail.active:
			var field: PackedFloat32Array = _terrain.height_samples.duplicate()
			for i in range(field.size()):
				field[i] *= _terrain.relief_scale()
			var size: Vector2i = _terrain.sample_size()
			var texture := ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, field.to_byte_array()))
			_river_material.set_shader_parameter("height_coarse", texture)
			_river_material.set_shader_parameter("height_fine", texture)
			_river_material.set_shader_parameter("field_blend", 1.0)
		_process(0)


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


func _index_lake(clipped: Array[Vector3], level: float) -> void:
	var polygon := PackedVector2Array()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for vertex in clipped:
		var point := Vector2(vertex.x, vertex.z)
		polygon.append(point)
		low = low.min(point)
		high = high.max(point)
	var id: int = _lake_polygons.size()
	_lake_polygons.append({"polygon": polygon, "level": level})
	var a := Vector2i((low / _bucket_size).floor())
	var b := Vector2i((high / _bucket_size).floor())
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var key := Vector2i(x, y)
			if not _lake_buckets.has(key):
				_lake_buckets[key] = []
			_lake_buckets[key].append(id)

func water_level_at(point: Vector2) -> float:
	var bed: float = _surface(point)
	var found: float = NAN
	for id in _lake_buckets.get(Vector2i((point / _bucket_size).floor()), []):
		var lake: Dictionary = _lake_polygons[id]
		if bed < lake.level + 0.00001 and Geometry2D.is_point_in_polygon(point, lake.polygon):
			found = lake.level if is_nan(found) else maxf(found, lake.level)
	if not is_nan(found):
		return found
	var sea: float = _terrain.sea_level * _terrain.relief_scale()
	if bed <= sea:
		var cell: int = _terrain.graph.nearest_cell(point)
		if _terrain.hydrology.lake_ids[cell] < 0:
			return sea
	return NAN

func _bank_point(center: Vector2, bank: Vector2) -> Vector2:
	if is_nan(water_level_at(bank)):
		return bank
	var a: Vector2 = center
	var b: Vector2 = bank
	for i in range(10):
		var middle: Vector2 = (a + b) * 0.5
		if is_nan(water_level_at(middle)):
			a = middle
		else:
			b = middle
	return a.move_toward(center, maxf(_terrain.map_size.x, _terrain.map_size.y) * 0.000001)

func _dry_spans(points: PackedVector3Array, widths: PackedFloat32Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var distance: float = 0
	var step_size: float = maxf(0.05, _terrain.graph.spacing * 0.08)
	for i in range(points.size() - 1):
		var steps: int = maxi(1, ceili(points[i].distance_to(points[i + 1]) / step_size))
		for step in range(steps):
			var t0: float = float(step) / steps
			var t1: float = float(step + 1) / steps
			var a: Vector3 = points[i].lerp(points[i + 1], t0)
			var b: Vector3 = points[i].lerp(points[i + 1], t1)
			var wa: float = lerpf(widths[i], widths[i + 1], t0)
			var wb: float = lerpf(widths[i], widths[i + 1], t1)
			var pa: Vector2 = Vector2(a.x, a.z) + _terrain.map_size * 0.5
			var pb: Vector2 = Vector2(b.x, b.z) + _terrain.map_size * 0.5
			var la: float = water_level_at(pa)
			var lb: float = water_level_at(pb)
			var wet_a: bool = not is_nan(la)
			var wet_b: bool = not is_nan(lb)
			if wet_a and wet_b:
				distance += a.distance_to(b)
				continue
			var level: float = _terrain.sea_level * _terrain.relief_scale()
			if wet_a != wet_b:
				var low: float = 0
				var high: float = 1
				for iteration in range(12):
					var middle: float = (low + high) * 0.5
					if (not is_nan(water_level_at(pa.lerp(pb, middle)))) == wet_a:
						low = middle
					else:
						high = middle
				var inset: float = maxf(_terrain.map_size.x, _terrain.map_size.y) * 0.000001 / maxf(0.00001, pa.distance_to(pb))
				var t: float = minf(1, high + inset) if wet_a else maxf(0, low - inset)
				var cut: Vector3 = a.lerp(b, t)
				var width: float = lerpf(wa, wb, t)
				level = la if wet_a else lb
				if wet_a:
					a = cut
					wa = width
				else:
					b = cut
					wb = width
			if a.distance_squared_to(b) > 0.00000001:
				var aa: Vector2 = Vector2(a.x, a.z) + _terrain.map_size * 0.5
				var bb: Vector2 = Vector2(b.x, b.z) + _terrain.map_size * 0.5
				a.y = _surface(aa)
				b.y = _surface(bb)
				result.append({"a": a, "b": b, "wa": wa, "wb": wb, "distance": distance, "level": level})
			distance += a.distance_to(b)
	return result

func _index_river(a: Vector2, b: Vector2, radius: float) -> void:
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

func _process(_delta: float) -> void:
	if _river_material != null and _terrain.detail != null and _terrain.detail.active:
		var key := Vector2(_terrain.detail.current_level, _terrain.detail.blend)
		if key != _lod_key:
			_lod_key = key
			_terrain.detail.apply_surface_state(_river_material)
