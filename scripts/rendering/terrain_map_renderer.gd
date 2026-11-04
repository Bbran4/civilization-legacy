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
var _province_kinds: ImageTexture
var _nation_colors: ImageTexture
var _nation_source: RefCounted
var _nation_revision := -1
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
	if enabled and layer != null:
		_update_nation_colors(layer)
	provinces_visible = enabled and layer != null and not preview
	borders.update(layer,map_extent,provinces_visible and shaded_relief)
	material.set_shader_parameter("vector_borders",enabled and layer != null and not preview)
	material.set_shader_parameter("provinces_enabled", enabled)
	material.set_shader_parameter("province_field", layer.texture() if enabled else null)

func _update_nation_colors(layer: RefCounted) -> void:
	if _nation_source == layer and _nation_revision == layer.border_revision: return
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
	var kinds := Image.create(256,256,false,Image.FORMAT_R8)
	image.fill(Color(0,0,0,0))
	for record in layer.records:
		if record.kind != "land":
			kinds.set_pixel(record.id % 256,record.id / 256,Color(1,0,0))
			continue
		var color: Color = layer.nation_color(int(record.get("nation_id",0)))
		if color.a > 0.0: image.set_pixel(record.id % 256,record.id / 256,color)
	if _nation_colors == null: _nation_colors = ImageTexture.create_from_image(image)
	else: _nation_colors.update(image)
	if _province_kinds == null: _province_kinds = ImageTexture.create_from_image(kinds)
	else: _province_kinds.update(kinds)
	material.set_shader_parameter("province_kinds",_province_kinds)
	_nation_source = layer
	_nation_revision = layer.border_revision
	material.set_shader_parameter("nation_colors",_nation_colors)

func set_border_appearance(settings: Dictionary) -> void:
	borders.configure(settings)
	material.set_shader_parameter("smooth_borders",settings.smooth)

func set_paint(layer: RefCounted, enabled: bool) -> void:
	material.set_shader_parameter("paint_enabled",enabled and layer != null)
	material.set_shader_parameter("paint_field",layer.texture if layer != null else null)
