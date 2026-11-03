shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D height_field : filter_linear, repeat_disable;
uniform vec2 texel_size = vec2(0.001);
uniform bool shaded_relief = true;
uniform bool height_enabled = true;
uniform bool water_enabled = false;
uniform sampler2D water_field : filter_linear, repeat_disable;
void fragment() {
	float h = texture(height_field, UV).r;
	float value = h;
	if (shaded_relief) {
		float dx = texture(height_field, UV + vec2(texel_size.x, 0.0)).r - texture(height_field, UV - vec2(texel_size.x, 0.0)).r;
		float dy = texture(height_field, UV + vec2(0.0, texel_size.y)).r - texture(height_field, UV - vec2(0.0, texel_size.y)).r;
		float resolution_scale = float(max(textureSize(height_field, 0).x, textureSize(height_field, 0).y)) / 1025.0;
		vec3 n = normalize(vec3(-dx * 45.0 * resolution_scale, 1.0, -dy * 45.0 * resolution_scale));
		float light = 0.55 + 0.45 * max(dot(n, normalize(vec3(-0.6, 0.8, -0.4))), 0.0);
		value = h < 0.2 ? h * 0.35 : clamp(0.25 + h * 0.7, 0.0, 1.0) * light;
	}
	vec3 color = height_enabled ? vec3(value) : vec3(0.02);
	if (water_enabled && (shaded_relief || !height_enabled)) {
		vec2 water = texture(water_field, UV).rg;
		color = mix(color, vec3(0.223529, 0.498039, 0.658824), water.r);
		color = mix(color, vec3(0.156863, 0.403922, 0.537255), water.g);
	}
	ALBEDO = color;
}
