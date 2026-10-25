shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
uniform vec4 water_colour : source_color = vec4(0.14, 0.43, 0.57, 1.0);
void fragment() {
	ALBEDO = mix(water_colour.rgb * 1.18, water_colour.rgb * 0.72, COLOR.r);
	ROUGHNESS = 1.0;
}
