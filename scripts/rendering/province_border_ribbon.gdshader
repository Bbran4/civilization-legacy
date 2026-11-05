shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://scripts/rendering/map_geography.gdshaderinc"
#include "res://scripts/rendering/map_relief.gdshaderinc"
uniform sampler2D province_field : filter_nearest, repeat_disable;
uniform bool land_border = true;
uniform bool unassigned_border = false;
varying vec2 map_uv;
uniform vec2 map_extent = vec2(192.0);
uniform float width_pixels = 1.3;
uniform int border_style = 0;
uniform float distant_scale = 0.35;
uniform float reference_width = 1.0;
uniform float dash_length = 2.4;
void vertex() {
	vec2 normal = COLOR.rg*2.0-1.0;
	vec3 center = vec3(VERTEX.x,relief_height(UV2),VERTEX.z);
	vec2 cell_world = map_extent/vec2(textureSize(relief_vertices,0)-1);
	if (chunked_relief) {
		ivec2 patch = clamp(ivec2(floor(UV2*vec2(relief_patch_count))),ivec2(0),relief_patch_count-1);
		float level = round(texelFetch(relief_patch_lods,patch,0).r*255.0);
		cell_world = map_extent/(vec2(relief_patch_count)*8.0*exp2(level));
	}
	float probe = max(min(cell_world.x,cell_world.y)*0.25,0.0001);
	vec2 direction = normal*(UV.y < 0.0 ? -1.0 : 1.0);
	vec3 neighbor = center+vec3(direction.x,0.0,direction.y)*probe;
	neighbor.y = relief_height(UV2+direction*probe/map_extent);
	vec4 clip = PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(center,1.0);
	vec4 next = PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(neighbor,1.0);
	vec2 screen_x = (PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(1.0,0.0,0.0,0.0)).xy*VIEWPORT_SIZE*0.5;
	vec2 screen_y = (PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xy*VIEWPORT_SIZE*0.5;
	float stable_pixels = max(max(length(screen_x),length(screen_y)),0.0001);
	// A surface normal can point almost into the camera on a steep face. Never
	// turn that projection singularity into an unbounded world offset or lift.
	float pixels_per_world = max(length((next.xy/next.w-clip.xy/clip.w)*VIEWPORT_SIZE*0.5)/probe,stable_pixels*0.2);
	float zoom_scale = mix(distant_scale,1.0,smoothstep(0.5,3.0,pixels_per_world*reference_width));
	float half_width = min(width_pixels*zoom_scale*0.5/pixels_per_world,max(cell_world.x,cell_world.y)*0.5);
	float offset = half_width*UV.y;
	map_uv = UV2+normal*offset/map_extent;
	// Expand on the terrain, not in clip space at the centerline's old depth.
	// A subpixel bias replaces the fixed lift that floated visibly at deep zoom.
	VERTEX.xz += normal*offset;
	VERTEX.y = relief_height(map_uv)+0.35/stable_pixels;
	POSITION = PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(VERTEX,1.0);
}
// Integrate each horizontal slice of the oval over the pixel footprint.
// At distance this converges to coverage rather than shimmering between gaps.
float dash_integral(float x, float half_span) {
    return floor(x) * (2.0 * half_span)
        + clamp(fract(x) - (0.5 - half_span), 0.0, 2.0 * half_span);
}
void fragment() {
    // Derivatives must be evaluated before geographic clipping diverges a quad.
    float across_derivative = fwidth(UV.y);
    float along_derivative = fwidth(UV.x/dash_length);
    if (geographic_land(map_uv) != land_border) discard;
    // ID zero includes lakes/ocean and deliberately erased impassable land.
    // Only the latter is a political boundary; geography owns the former.
    if (land_border && unassigned_border) {
        vec2 texel = 1.0/vec2(textureSize(province_field,0));
        float blocked = 0.0;
        for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
            blocked = max(blocked,round(texture(province_field,map_uv+vec2(float(x),float(y))*texel).b*255.0)==3.0 ? 1.0 : 0.0);
        }
        if (blocked < 0.5) discard;
    }
    float aa = max(across_derivative, 0.02);
    float across = abs(UV.y);
    float edge = 1.0 - smoothstep(1.0-aa, 1.0, across);
    vec3 color = vec3(0.055, 0.065, 0.07);
    float alpha = edge;
    if (border_style == 0) {
        float along = UV.x / dash_length;
        float footprint = max(along_derivative, 0.005);
        // Soft oval ends, 52% ink at the center, tapering towards the sides.
        // Average four cross-ribbon samples to filter subpixel line widths too.
        float coverage = 0.0;
        for (int i = 0; i < 4; i++) {
            float y = UV.y + (float(i) / 3.0 - 0.5) * across_derivative;
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
