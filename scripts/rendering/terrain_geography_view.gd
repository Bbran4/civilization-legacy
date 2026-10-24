extends Node3D
## Fixed shoreline lines for the flat overview; never rebuild while zooming.

const SHADER = preload("res://scripts/rendering/shoreline.gdshader")
var _lines: MeshInstance3D
var _material: ShaderMaterial
var _overview: float = 1.0
var _heights_view: bool = false


func clear() -> void:
	if is_instance_valid(_lines):
		_lines.free()
	_lines = null
	_material = null


func build(geography: RefCounted, extent: Vector2, sea: float, colour: Color) -> void:
	clear()
	if geography == null or geography.coastlines.is_empty():
		return
	var vertices := PackedVector3Array()
	for coast in geography.coastlines:
		for index in range(coast.points.size() if coast.closed else coast.points.size() - 1):
			for point in [coast.points[index], coast.points[(index + 1) % coast.points.size()]]:
				vertices.append(Vector3(point.x - extent.x * 0.5, sea, point.y - extent.y * 0.5))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = 1
	_material.set_shader_parameter("shore_color", colour.lightened(0.2))
	_lines = MeshInstance3D.new()
	_lines.name = "Shorelines"
	_lines.mesh = mesh
	_lines.material_override = _material
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines, false, Node.INTERNAL_MODE_BACK)
	_update_visibility()


func set_overview_blend(value: float) -> void:
	_overview = value
	_update_visibility()


func set_heightmap_view(value: bool) -> void:
	_heights_view = value
	_update_visibility()


func _update_visibility() -> void:
	if is_instance_valid(_lines):
		_lines.visible = _overview > 0.001 and not _heights_view
		_material.set_shader_parameter("overview_blend", _overview)
