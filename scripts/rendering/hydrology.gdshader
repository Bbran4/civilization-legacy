shader_type spatial;
// Opaque water surfaces use ordinary depth testing, including foreground mountains.
render_mode unshaded, cull_disabled;
uniform vec4 water_colour : source_color = vec4(0.14, 0.43, 0.57, 1.0);
uniform bool river_mode = false;
uniform vec2 map_size = vec2(1024.0);
uniform float surface_lift = 0.012;
#include "res://scripts/rendering/terrain_height_sampling.gdshaderinc"
varying vec2 water_position;
varying mat4 water_to_view;
varying float terminal_level;
void vertex() {
	water_position = VERTEX.xz;
	water_to_view = MODELVIEW_MATRIX;
	terminal_level = UV2.x;
	if (river_mode) { VERTEX.y = displayed_height(VERTEX.xz) + surface_lift; }
}
void fragment() {
	DEPTH = FRAGCOORD.z;
	vec3 colour = mix(water_colour.rgb * 1.18, water_colour.rgb * 0.72, COLOR.r);
	if (river_mode) {
		if (displayed_height(water_position) <= terminal_level + 0.00001) { discard; }
		vec4 clip = PROJECTION_MATRIX * water_to_view * vec4(water_position.x, displayed_height(water_position) + surface_lift, water_position.y, 1.0);
		float ndc = clip.z / clip.w;
		DEPTH = OUTPUT_IS_SRGB ? ndc * 0.5 + 0.5 : ndc;
		float phase = UV.y * 4.0 - TIME * 1.8;
		float ripple = sin(phase + sin(UV.x * 19.0 + phase * 0.23)) * 0.5 + 0.5;
		float banks = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
		colour *= mix(0.82, 1.12, ripple) * mix(0.8, 1.0, banks);
		float foam = COLOR.g * smoothstep(0.35, 0.85, ripple);
		colour = mix(colour, vec3(0.83, 0.92, 0.92), foam * 0.85);
	}
	ALBEDO = colour;
	ROUGHNESS = 0.7;
}
