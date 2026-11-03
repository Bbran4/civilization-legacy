extends RefCounted
## Shared terrain presentation for authoring and runtime maps; no editor dependency.
const SHADER = preload("res://scripts/rendering/terrain_map.gdshader")
var surface: MeshInstance3D
var material := ShaderMaterial.new()
var shaded_relief := true

func _init(target: MeshInstance3D) -> void:
	surface = target
	material.shader = SHADER
	surface.material_override = material

func set_heightfield(samples: PackedFloat32Array, size: Vector2i, extent: Vector2, height_offset: float, elevation: float, generator_version: int) -> void:
	assert(samples.size() == size.x * size.y and elevation > 0.0)
	var normalized := PackedFloat32Array()
	normalized.resize(samples.size())
	for i in range(samples.size()):
		normalized[i] = clampf((samples[i] - height_offset) / elevation + (0.2 if generator_version >= 3 else 0.0), 0.0, 1.0)
	var plane := PlaneMesh.new()
	plane.size = extent
	surface.mesh = plane
	surface.material_override = material
	material.set_shader_parameter("height_field", ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, normalized.to_byte_array())))
	material.set_shader_parameter("texel_size", Vector2.ONE / Vector2(size))
	set_shaded_relief(shaded_relief)

func set_shaded_relief(enabled: bool) -> void:
	shaded_relief = enabled
	material.set_shader_parameter("shaded_relief", enabled)
