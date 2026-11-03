shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float width_pixels = 1.3;
uniform int border_style = 0;
uniform float distant_scale = 0.35;
uniform float reference_width = 1.0;
uniform float dash_length = 2.4;
void vertex() {
	vec2 normal = COLOR.rg * 2.0 - 1.0;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX,1.0);
	vec4 neighbor = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX + vec3(normal.x,0.0,normal.y),1.0);
	vec2 direction = (neighbor.xy/neighbor.w - clip.xy/clip.w) * VIEWPORT_SIZE;
	direction = normalize(direction + vec2(0.0000001));
	float pixels_per_reference = length((neighbor.xy/neighbor.w - clip.xy/clip.w) * VIEWPORT_SIZE * 0.5) * reference_width;
	float zoom_scale = mix(distant_scale,1.0,smoothstep(0.5,3.0,pixels_per_reference));
	clip.xy += direction * (width_pixels * zoom_scale * 0.5) * UV.y * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}
// Integrate each horizontal slice of the oval over the pixel footprint.
// At distance this converges to coverage rather than shimmering between gaps.
float dash_integral(float x, float half_span) {
    return floor(x) * (2.0 * half_span)
        + clamp(fract(x) - (0.5 - half_span), 0.0, 2.0 * half_span);
}
void fragment() {
    float aa = max(fwidth(UV.y), 0.02);
    float across = abs(UV.y);
    float edge = 1.0 - smoothstep(1.0-aa, 1.0, across);
    vec3 color = vec3(0.055, 0.065, 0.07);
    float alpha = edge;
    if (border_style == 0) {
        float along = UV.x / dash_length;
        float footprint = max(fwidth(along), 0.005);
        // Soft oval ends, 52% ink at the center, tapering towards the sides.
        // Average four cross-ribbon samples to filter subpixel line widths too.
        float coverage = 0.0;
        for (int i = 0; i < 4; i++) {
            float y = UV.y + (float(i) / 3.0 - 0.5) * fwidth(UV.y);
            float span = 0.26 * sqrt(max(0.0, 1.0 - y*y));
            coverage += (dash_integral(along + footprint*0.5, span)
                - dash_integral(along - footprint*0.5, span)) / footprint;
        }
        alpha = clamp(coverage * 0.25, 0.0, 1.0) * 0.8;
        color = vec3(0.12, 0.115, 0.105);
    }
    ALBEDO = color;
    ALPHA = alpha;
}
