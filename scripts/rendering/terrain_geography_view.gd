extends Node3D
## Fixed triangle shore ribbons; camera width and terrain draping happen on the GPU.
const SHADER = preload("res://scripts/rendering/shoreline.gdshader")
const Geography = preload("res://scripts/domain/terrain_geography.gd")
var _ribbons: MeshInstance3D
var _material: ShaderMaterial
var _overview: float = 1.0
var _heights_view: bool = false
var _mode: int = 0
var _terrain: Node
var _source_key: Array = []
var _lod_key := Vector2(-1, -1)
var build_count: int = 0
var path_count: int = 0
var segment_count: int = 0
var bevel_count: int = 0


func clear() -> void:
	if is_instance_valid(_ribbons):
		_ribbons.free()
	_ribbons = null
	_material = null
	_lod_key = Vector2(-1, -1)
	_source_key.clear()
	path_count = 0
	segment_count = 0
	bevel_count = 0


func build(terrain: Node) -> void:
	_terrain = terrain
	var detail = terrain.detail
	var usable: bool = terrain.geography != null and terrain.show_water and is_equal_approx(terrain.sea_level, terrain.height_offset)
	var key: Array = [terrain.geography.source_hash if terrain.geography != null else "", detail.build_count if detail != null else -1, detail.active if detail != null else false, terrain.elevation, terrain.height_offset, terrain.sea_level, terrain.sand_color, usable]
	if key == _source_key:
		return
	if not usable:
		clear()
		_source_key = key
		return
	var sea: float = terrain.sea_level * terrain.relief_scale()
	var field: PackedFloat32Array
	var size: Vector2i
	if detail != null and detail.active:
		field = detail.field_heights
		size = detail.field_size
	else:
		field = terrain.height_samples.duplicate()
		for i in range(field.size()):
			field[i] *= terrain.relief_scale()
		size = terrain.sample_size()
	# The same triangle-contour implementation, sampled from the fixed rendered height field.
	var paths: Array[Dictionary] = Geography.new().trace_display_contours(field, size, terrain.map_size, sea)
	var filter: Callable = terrain.hydrology.is_ocean_coast.bind(terrain.graph) if terrain.hydrology != null and terrain.hydrology.error.is_empty() else Callable()
	build_paths(paths, terrain.map_size, sea, terrain.sand_color, filter)
	_source_key = key
	if _material == null:
		return
	_material.set_shader_parameter("surface_following", true)
	if detail == null or not detail.active:
		var texture := ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, field.to_byte_array()))
		set_surface_fields(texture, texture, 1.0)
	else:
		_process(0)


func _join(points: PackedVector2Array, index: int, closed: bool, direction: Vector2, connected: bool) -> Vector3:
	var normal := Vector2(-direction.y, direction.x)
	if not connected or (not closed and (index == 0 or index == points.size() - 1)):
		return Vector3(normal.x, normal.y, 1)
	var incoming: Vector2 = (points[index] - points[posmod(index - 1, points.size())]).normalized()
	var outgoing: Vector2 = (points[(index + 1) % points.size()] - points[index]).normalized()
	var miter: Vector2 = Vector2(-incoming.y - outgoing.y, incoming.x + outgoing.x).normalized()
	var denominator: float = miter.dot(Vector2(-outgoing.y, outgoing.x))
	if denominator < 0.5:
		return Vector3(normal.x, normal.y, 1) # Separate bevel wedge, never a long spike.
	return Vector3(miter.x, miter.y, 1.0 / denominator)


func _projection_angle(points: PackedVector2Array, index: int, closed: bool) -> float:
	var incoming: Vector2 = (points[index] - points[posmod(index - 1, points.size())]).normalized() if closed or index > 0 else (points[1] - points[0]).normalized()
	var outgoing: Vector2 = (points[(index + 1) % points.size()] - points[index]).normalized() if closed or index + 1 < points.size() else incoming
	var direction := Vector2(-incoming.y - outgoing.y, incoming.x + outgoing.x)
	if direction.length_squared() < 0.000001:
		direction = Vector2(-outgoing.y, outgoing.x)
	return direction.angle()


func build_paths(paths: Array[Dictionary], extent: Vector2, sea: float, colour: Color, coast_filter: Callable = Callable()) -> void:
	clear()
	build_count += 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var joins := PackedVector2Array()
	var indices := PackedInt32Array()
	for path in paths:
		var points := PackedVector2Array()
		for point in path.points:
			if points.is_empty() or point.distance_squared_to(points[-1]) > 0.00000001:
				points.append(point)
		if path.closed and points.size() > 1 and points[0].distance_squared_to(points[-1]) < 0.00000001:
			points.resize(points.size() - 1)
		if points.size() < (3 if path.closed else 2):
			continue
		var count: int = points.size() if path.closed else points.size() - 1
		var enabled: Array[bool] = []
		for i in range(count):
			enabled.append(not coast_filter.is_valid() or coast_filter.call((points[i] + points[(i + 1) % points.size()]) * 0.5))
		path_count += 1
		var distance: float = 0
		for i in range(count):
			var next: int = (i + 1) % points.size()
			var length: float = points[i].distance_to(points[next])
			if enabled[i]:
				var direction: Vector2 = (points[next] - points[i]) / length
				var start_join: Vector3 = _join(points, i, path.closed, direction, enabled[posmod(i - 1, count)] if path.closed or i > 0 else false)
				var end_join: Vector3 = _join(points, next, path.closed, direction, enabled[(i + 1) % count] if path.closed or i + 1 < count else false)
				var base: int = vertices.size()
				for endpoint in range(2):
					var point: Vector2 = points[i] if endpoint == 0 else points[next]
					var join: Vector3 = start_join if endpoint == 0 else end_join
					for side in [-1.0, 1.0]:
						vertices.append(Vector3(point.x - extent.x * 0.5, sea, point.y - extent.y * 0.5))
						normals.append(Vector3(join.x, 0, join.y))
						uvs.append(Vector2(distance + length * endpoint, side))
						joins.append(Vector2(join.z, _projection_angle(points, i if endpoint == 0 else next, path.closed)))
				indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
				segment_count += 1
				if (path.closed or i > 0) and enabled[posmod(i - 1, count)]:
					var incoming: Vector2 = (points[i] - points[posmod(i - 1, points.size())]).normalized()
					if incoming.dot(direction) < -0.5:
						var side: float = -1.0 if incoming.cross(direction) > 0 else 1.0
						base = vertices.size()
						for entry in [Vector3(0, 0, 0), Vector3(-incoming.y, incoming.x, side), Vector3(-direction.y, direction.x, side)]:
							vertices.append(Vector3(points[i].x - extent.x * 0.5, sea, points[i].y - extent.y * 0.5))
							normals.append(Vector3(entry.x, 0, entry.y) if entry.z != 0 else Vector3.RIGHT)
							uvs.append(Vector2(distance, entry.z))
							joins.append(Vector2(1, _projection_angle(points, i, path.closed)))
						indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
						bevel_count += 1
			distance += length
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = joins
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 2
	_material.set_shader_parameter("shore_color", colour.lightened(0.12))
	_material.set_shader_parameter("map_size", extent)
	_material.set_shader_parameter("sea_level", sea)
	_material.set_shader_parameter("max_half_width", maxf(extent.x, extent.y) * 0.0025)
	_ribbons = MeshInstance3D.new()
	_ribbons.name = "ShoreRibbons"
	_ribbons.mesh = mesh
	_ribbons.material_override = _material
	_ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Shader extrusion and draping extend beyond the centerline bounds.
	var padding: float = maxf(extent.x, extent.y) * 0.005 + 0.02
	if is_instance_valid(_terrain) and _terrain.detail != null and _terrain.detail.active:
		padding += (extent / Vector2(_terrain.detail.height_textures[0].get_size() - Vector2.ONE)).length() * 1.5
	_ribbons.custom_aabb = AABB(Vector3(-extent.x * 0.5 - padding, sea - extent.length(), -extent.y * 0.5 - padding), Vector3(extent.x + padding * 2, extent.length() * 2, extent.y + padding * 2))
	add_child(_ribbons, false, Node.INTERNAL_MODE_BACK)
	_update_visibility()


func set_surface_fields(coarse: Texture2D, fine: Texture2D, blend: float) -> void:
	if _material != null:
		_material.set_shader_parameter("height_coarse", coarse)
		_material.set_shader_parameter("height_fine", fine)
		_material.set_shader_parameter("field_blend", blend)


func _process(_delta: float) -> void:
	if _material == null or not is_instance_valid(_terrain) or _terrain.detail == null or not _terrain.detail.active:
		return
	var detail = _terrain.detail
	var key := Vector2(detail.current_level, detail.blend)
	if key != _lod_key:
		_lod_key = key
		set_surface_fields(detail.height_textures[maxi(0, detail.current_level - 1)], detail.height_textures[detail.current_level], detail.blend)


func set_overview_blend(value: float) -> void:
	_overview = clampf(value, 0, 1)
	_update_visibility()


func set_heightmap_view(value: bool) -> void:
	_heights_view = value
	_update_visibility()


func set_climate_view(mode: int) -> void:
	_mode = mode
	_update_visibility()


func _update_visibility() -> void:
	if is_instance_valid(_ribbons):
		_ribbons.visible = not _heights_view and _mode == 0
		_material.set_shader_parameter("overview_blend", _overview)
