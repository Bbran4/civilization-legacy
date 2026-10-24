shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;

uniform vec4 shore_color : source_color = vec4(0.85, 0.80, 0.62, 1.0);
uniform float overview_blend = 1.0;

void fragment() {
	ALBEDO = shore_color.rgb;
	ALPHA = shore_color.a * overview_blend;
}
