shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D height_field : filter_linear, repeat_disable;
uniform vec2 texel_size = vec2(0.001);
uniform bool shaded_relief = true;
uniform bool height_enabled = true;
uniform bool water_enabled = false;
uniform sampler2D water_field : filter_linear, repeat_disable;
uniform bool provinces_enabled = false;
uniform int selected_province = 0;
uniform sampler2D province_field : filter_nearest, repeat_disable;
float province_id(vec2 uv) {
	vec2 c = round(texture(province_field, uv).rg * 255.0);
	return c.r + c.g * 256.0;
}
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
	if (provinces_enabled && shaded_relief) {
		float id = province_id(UV);
		if (id > 0.5) {
			bool ocean = texture(province_field, UV).b > 0.001;
			vec3 tint = 0.3 + 0.6 * fract(sin(vec3(id, id + 17.0, id + 43.0)) * 43758.5453);
			color = ocean ? mix(vec3(0.035, 0.10, 0.16), vec3(0.06, 0.19, 0.28) + tint * 0.055, 0.7) : mix(color, tint * (0.45 + value * 0.7), 0.62);
			vec2 border_step = max(texel_size, fwidth(UV) * 1.25);
			bool edge = province_id(UV + vec2(border_step.x, 0.0)) != id || province_id(UV + vec2(0.0, border_step.y)) != id;
			if (edge) color = ocean ? vec3(0.16, 0.32, 0.43) : color * 0.35;
			if (int(id) == selected_province) color = mix(color, vec3(1.0, 0.8, 0.3), 0.45);
		}
	}
	if (water_enabled && (shaded_relief || !height_enabled)) {
		vec2 water = texture(water_field, UV).rg;
		color = mix(color, vec3(0.223529, 0.498039, 0.658824), water.r);
		color = mix(color, vec3(0.156863, 0.403922, 0.537255), water.g);
	}
	ALBEDO = color;
}
