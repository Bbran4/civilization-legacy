shader_type spatial;
render_mode cull_disabled;
uniform sampler2D coverage : filter_linear, repeat_disable;
uniform vec2 map_size;

void fragment() {
	if (texture(coverage, (UV + vec2(0.5)) / map_size).r < 0.5) { discard; }
	float wave = sin(UV.x * 0.6 + TIME * 0.8) * sin(UV.y * 0.4 - TIME * 0.55);
	ALBEDO = mix(vec3(0.025, 0.19, 0.25), vec3(0.055, 0.30, 0.36), wave * 0.15 + 0.5);
	EMISSION = vec3(0.004, 0.012, 0.016);
	ROUGHNESS = 0.35;
	METALLIC = 0.0;
	NORMAL_MAP = vec3(0.5 + wave * 0.025, 0.5 + cos(UV.y + TIME) * 0.015, 1.0);
}
