extends Node3D
## Chunked miniature forests; instance placement is fixed until terrain/climate edits.
const Layout = preload("res://scripts/rendering/terrain_vegetation_layout.gd")
const Library = preload("res://scripts/rendering/terrain_tree_library.gd")
var layout: RefCounted
var groups: Array[Dictionary] = []
var build_count: int = 0
var _terrain: Node
var _material: ShaderMaterial
var _materials: Array[ShaderMaterial] = []
var _meshes: Array[ArrayMesh] = []
var _type_count: int = 0
var _overview: float = 1
var _mode: int = 0
var _heights: bool = false
var _lod_key := Vector2(-1, -1)
var _simple: bool = false
var _shadows: bool = false
var fade: float = 0

func clear() -> void:
	for group in groups:
		group.node.free()
	groups.clear()
	layout = null
	_material = null
	_materials.clear()
	_meshes.clear()
	_lod_key = Vector2(-1, -1)

func build(terrain: Node) -> void:
	clear()
	_terrain = terrain
	build_count += 1
	layout = Layout.new()
	layout.generate(terrain)
	if layout.instances.is_empty():
		return
	Library.ensure_library(terrain.tree_catalog)
	_type_count = terrain.tree_catalog.definitions.size()
	for source in Library.meshes:
		var mesh: ArrayMesh = source.duplicate()
		for surface in range(mesh.get_surface_count()):
			var material: ShaderMaterial = source.surface_get_material(surface).duplicate()
			material.set_shader_parameter("map_size", terrain.map_size)
			material.set_shader_parameter("world_to_terrain", terrain.global_transform.affine_inverse())
			if terrain.detail == null or not terrain.detail.active:
				var field: PackedFloat32Array = terrain.height_samples.duplicate()
				for i in range(field.size()):
					field[i] *= terrain.relief_scale()
				var size: Vector2i = terrain.sample_size()
				var texture := ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, field.to_byte_array()))
				material.set_shader_parameter("height_coarse", texture)
				material.set_shader_parameter("height_fine", texture)
				material.set_shader_parameter("field_blend", 1.0)
			mesh.surface_set_material(surface, material)
			_materials.append(material)
		_meshes.append(mesh)
	if _materials.is_empty():
		return
	_material = _materials[0]
	var buckets: Dictionary = {}
	var side: float = maxf(64, maxf(terrain.map_size.x, terrain.map_size.y) / 16.0)
	for tree in layout.instances:
		var key := Vector3i(floori(tree.point.x / side), floori(tree.point.y / side), tree.kind)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(tree)
	for key in buckets:
		var trees: Array = buckets[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _meshes[key.z]
		multi.instance_count = trees.size()
		var low: float = INF
		var high: float = -INF
		for i in range(trees.size()):
			var tree: Dictionary = trees[i]
			var basis := Basis(Vector3.UP, tree.rotation).scaled(Vector3.ONE * tree.scale)
			var point: Vector2 = tree.point - terrain.map_size * 0.5
			multi.set_instance_transform(i, Transform3D(basis, Vector3(point.x, tree.height - 0.015, point.y)))
			multi.set_instance_color(i, Color(tree.tint, tree.tint, tree.tint, 1))
			low = minf(low, tree.height)
			high = maxf(high, tree.height)
		var margin: float = maxf(3, terrain.elevation * terrain.relief_scale())
		var bounds: AABB = _meshes[key.z].get_aabb().merge(_meshes[key.z + _type_count].get_aabb())
		var radius: float = Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z))).length() * 1.2
		var bottom: float = minf(0, bounds.position.y * 1.2)
		var top: float = maxf(0, bounds.end.y * 1.2)
		multi.custom_aabb = AABB(Vector3(key.x * side - terrain.map_size.x * 0.5 - radius, low - margin + bottom, key.y * side - terrain.map_size.y * 0.5 - radius), Vector3(side + radius * 2, high - low + margin * 2 + top - bottom, side + radius * 2))
		var node := MultiMeshInstance3D.new()
		node.name = "Trees_%d_%d_%d" % [key.x, key.y, key.z]
		node.multimesh = multi
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node, false, Node.INTERNAL_MODE_BACK)
		groups.append({"node": node, "kind": key.z})
	_simple = false
	_shadows = false
	_process(0)

func set_overview_blend(value: float) -> void:
	_overview = value
	_process(0)

func set_view(mode: int, heights: bool) -> void:
	_mode = mode
	_heights = heights
	_update_visibility()

func _update_visibility() -> void:
	visible = _mode == 0 and not _heights and _overview < 0.999 and fade > 0.001

func _process(_delta: float) -> void:
	if _material == null:
		visible = false
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var pixels: float = get_viewport().get_visible_rect().size.y / maxf(0.01, camera.size)
	fade = smoothstep(1.5, 3.5, pixels) * (1.0 - _overview)
	for material in _materials:
		material.set_shader_parameter("vegetation_fade", fade)
	var simple: bool = pixels < (10.0 if _simple else 8.0)
	var shadows: bool = pixels > (12.0 if _shadows else 16.0) and fade > 0.99
	if simple != _simple or shadows != _shadows:
		for group in groups:
			group.node.multimesh.mesh = _meshes[group.kind + (_type_count if simple else 0)]
			group.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_simple = simple
		_shadows = shadows
	if _terrain.detail != null and _terrain.detail.active:
		var key := Vector2(_terrain.detail.current_level, _terrain.detail.blend)
		if key != _lod_key:
			_lod_key = key
			for material in _materials:
				_terrain.detail.apply_surface_state(material)
	_update_visibility()
