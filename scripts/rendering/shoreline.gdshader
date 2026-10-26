shader_type spatial;
// Transparent edges retain the regular scene depth test; no through-terrain overlay.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 shore_color : source_color = vec4(0.85, 0.80, 0.62, 1.0);
uniform float overview_blend = 1.0;
uniform float overview_width_pixels = 1.6;
uniform float close_width_pixels = 1.25;
uniform float max_half_width = 2.0;
uniform vec2 map_size = vec2(1024.0);
uniform float sea_level = 0.0;
uniform bool surface_following = false;
#include "res://scripts/rendering/terrain_height_sampling.gdshaderinc"
varying float across;

void vertex() {
	vec4 projected_side = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(NORMAL, 0.0);
	float pixels_per_unit = length(projected_side.xy * VIEWPORT_SIZE * 0.5);
	float width_pixels = mix(close_width_pixels, overview_width_pixels, overview_blend);
	float half_width = min(width_pixels * 0.5 / max(pixels_per_unit, 0.001), max_half_width);
	if (surface_following) {
		// The fixed fine contour is projected onto the currently displayed sea edge.
		// Bounded local corrections avoid tracing new paths or rebuilding the mesh.
		vec2 center = VERTEX.xz;
		// Shared at each path node, including both sides of a bevel.
		vec2 projection_side = vec2(cos(UV2.y), sin(UV2.y));
		vec2 cell_size = map_size / vec2(textureSize(height_coarse, 0) - ivec2(1));
		float step_length = min(cell_size.x, cell_size.y) * 0.2;
		float max_shift = length(cell_size) * 1.5;
		float shift = 0.0;
		float error = displayed_height(center) - sea_level;
		for (int i = 0; i < 4; i++) {
			if (abs(error) < 0.00002) { break; }
			vec2 location = center + projection_side * shift;
			float derivative = (displayed_height(location + projection_side * step_length) - displayed_height(location - projection_side * step_length)) / (2.0 * step_length);
			if (abs(derivative) < 0.00001) { break; }
			float candidate = clamp(shift - error / derivative, -max_shift, max_shift);
			float next_error = displayed_height(center + projection_side * candidate) - sea_level;
			if (abs(next_error) >= abs(error)) { break; }
			shift = candidate;
			error = next_error;
		}
		VERTEX.xz = center + projection_side * shift;
	}
	VERTEX += NORMAL * UV.y * half_width * UV2.x;
	if (surface_following) {
		VERTEX.y = max(sea_level, displayed_height(VERTEX.xz));
	}
	float world_pixel = 2.0 / max(abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y, 0.001);
	VERTEX.y += clamp(world_pixel * 0.025, 0.0005, 0.01);
	across = UV.y;
}

void fragment() {
	float edge = 1.0 - smoothstep(0.45, 1.0, abs(across));
	ALBEDO = shore_color.rgb;
	ALPHA = shore_color.a * edge * mix(0.72, 0.95, overview_blend);
}
