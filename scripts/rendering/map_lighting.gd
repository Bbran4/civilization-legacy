extends RefCounted
## Shared presentation snapshot for the unshaded map materials. No world data.
var sun_direction := Vector3(-0.353,0.788,0.504).normalized()
var sun_color := Vector3(1.0,0.95,0.86)
var sky_color := Vector3(0.76,0.84,0.95)
var sun_strength := 0.4
var sky_strength := 0.67
var haze_focus := Vector3.ZERO
var haze_forward := Vector3.FORWARD
var haze_span := 100.0
var haze_strength := 0.0
func update(sun: DirectionalLight3D, environment: Environment, camera: Camera3D, focus: Vector3) -> void:
	if sun != null:
		sun_direction = sun.global_basis.z.normalized()
		sun_color = Vector3(sun.light_color.r,sun.light_color.g,sun.light_color.b)
		sun_strength = maxf(0.0,sun.light_energy)*0.4/0.85 if sun.visible else 0.0
	if environment != null:
		var color := environment.ambient_light_color
		sky_color = Vector3(color.r,color.g,color.b)
		sky_strength = maxf(0.0,environment.ambient_light_energy)*0.67/0.38
	haze_focus = focus
	if camera != null:
		haze_forward = -camera.global_basis.z.normalized()
		haze_span = maxf(1.0,camera.size)
		# Overhead maps remain clear. An oblique view receives only a light veil.
		haze_strength = sqrt(maxf(0.0,1.0-haze_forward.y*haze_forward.y))*0.10
func bind(target: ShaderMaterial) -> void:
	target.set_shader_parameter("map_sun_direction",sun_direction)
	target.set_shader_parameter("map_sun_color",sun_color)
	target.set_shader_parameter("map_sky_color",sky_color)
	target.set_shader_parameter("map_sun_strength",sun_strength)
	target.set_shader_parameter("map_sky_strength",sky_strength)
	target.set_shader_parameter("map_haze_focus",haze_focus)
	target.set_shader_parameter("map_haze_forward",haze_forward)
	target.set_shader_parameter("map_haze_span",haze_span)
	target.set_shader_parameter("map_haze_strength",haze_strength)
