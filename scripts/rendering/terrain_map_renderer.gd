extends RefCounted
## Shared terrain presentation for authoring and runtime maps; no editor dependency.
const Borders = preload("res://scripts/rendering/province_border_renderer.gd")
var borders: RefCounted
var map_extent := Vector2.ONE
const SHADER = preload("res://scripts/rendering/terrain_map.gdshader")
var surface: MeshInstance3D
var material := ShaderMaterial.new()
var shaded_relief := true
var provinces_visible := false
var _base_texture: ImageTexture
var rendered_heights := PackedFloat32Array()
var normalized_heights := PackedFloat32Array()

func _init(target: MeshInstance3D) -> void:
	surface = target
	material.shader = SHADER
	borders = Borders.new(surface)
	surface.material_override = material

func set_heightfield(samples: PackedFloat32Array, size: Vector2i, extent: Vector2, height_offset: float, elevation: float, generator_version: int) -> void:
	assert(samples.size() == size.x * size.y and elevation > 0.0)
	normalized_heights.resize(samples.size())
	for i in range(samples.size()):
		normalized_heights[i] = clampf((samples[i] - height_offset) / elevation + (0.2 if generator_version >= 3 else 0.0), 0.0, 1.0)
	map_extent = extent
	var plane := PlaneMesh.new()
	plane.size = extent
	surface.mesh = plane
	surface.material_override = material
	_base_texture = ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, normalized_heights.to_byte_array()))
	set_terrain_surface(null, false)
	material.set_shader_parameter("texel_size", Vector2.ONE / Vector2(size))
	set_shaded_relief(shaded_relief)

func set_shaded_relief(enabled: bool) -> void:
	shaded_relief = enabled
	borders.root.visible = enabled and provinces_visible
	material.set_shader_parameter("shaded_relief", enabled)

func set_water_layer(layer: RefCounted, enabled: bool) -> void:
	material.set_shader_parameter("water_enabled", enabled and layer != null)
	if layer != null and enabled:
		material.set_shader_parameter("water_field", layer.texture())
	else:
		material.set_shader_parameter("water_field", null)

func set_height_layer_visible(enabled: bool) -> void:
	material.set_shader_parameter("height_enabled", enabled)

func set_terrain_surface(layer: RefCounted, enabled: bool) -> void:
	rendered_heights = layer.heights if enabled and layer != null else normalized_heights
	material.set_shader_parameter("height_field", layer.texture() if enabled and layer != null else _base_texture)

func set_provinces(layer: RefCounted, enabled: bool, preview: bool = false) -> void:
	provinces_visible = enabled and layer != null and not preview
	borders.update(layer,map_extent,provinces_visible and shaded_relief)
	material.set_shader_parameter("vector_borders",enabled and layer != null and not preview)
	material.set_shader_parameter("provinces_enabled", enabled)
	material.set_shader_parameter("province_field", layer.texture() if enabled else null)
