shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D height_field : filter_linear, repeat_disable;
uniform vec2 texel_size = vec2(0.001);
uniform bool shaded_relief = true;
void fragment() {
	float h = texture(height_field, UV).r;
	float value = h;
	if (shaded_relief) {
		float dx = texture(height_field, UV + vec2(texel_size.x, 0.0)).r - texture(height_field, UV - vec2(texel_size.x, 0.0)).r;
		float dy = texture(height_field, UV + vec2(0.0, texel_size.y)).r - texture(height_field, UV - vec2(0.0, texel_size.y)).r;
		vec3 n = normalize(vec3(-dx * 45.0, 1.0, -dy * 45.0));
		float light = 0.55 + 0.45 * max(dot(n, normalize(vec3(-0.6, 0.8, -0.4))), 0.0);
		value = h < 0.2 ? h * 0.35 : clamp(0.25 + h * 0.7, 0.0, 1.0) * light;
	}
	ALBEDO = vec3(value);
}
