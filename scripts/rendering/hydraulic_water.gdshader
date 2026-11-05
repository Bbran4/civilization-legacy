shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
#include "res://scripts/rendering/map_relief.gdshaderinc"
#include "res://scripts/rendering/map_lighting.gdshaderinc"
uniform mat4 terrain_inverse = mat4(1.0);
uniform vec2 map_extent;
uniform sampler2D coverage : filter_linear, repeat_disable;
uniform sampler2D bed_field : filter_linear, repeat_disable;
uniform float height_scale;
uniform float offset_world;
uniform float datum;
uniform bool enabled = false;
varying float level;
void vertex() {
    if (chunked_relief) {
        UV=(terrain_inverse*MODEL_MATRIX*vec4(VERTEX,1.0)).xz/map_extent+0.5;
        level=patch_vertex_height(UV,int(round(COLOR.a*4.0)));
    } else {
        level=relief_height(UV)/max(relief_amount,0.00001);
    }
    VERTEX.y=level*relief_amount;
    POSITION=PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(VERTEX,1.0);
    POSITION.z+=0.000002*POSITION.w; // Compatibility reversed-Z bias at coincident banks.
}
void fragment() {
    vec2 wet=texture(coverage,UV).rg;
    float amount=max(wet.r,wet.g);
    if (!enabled || amount<0.004) discard;
    float bed=(texture(bed_field,UV).r-datum)*height_scale+offset_world;
    float depth=max(level-bed,0.0)/max(height_scale,0.0001);
    float absorption=1.0-exp(-100.0*depth);
    vec2 local=UV*map_extent;
    float wave_a = local.x*2.1 + local.y*1.7 - TIME*mix(1.5,0.6,wet.g);
    float wave_b = local.y*2.9 + TIME*0.8;
    vec3 ripple_normal = normalize(vec3(0.12*cos(wave_a),1.0,0.09*cos(wave_b)));
    float glint = pow(max(dot(reflect(-normalize(map_sun_direction),ripple_normal),normalize(mat3(INV_VIEW_MATRIX)*VIEW)),0.0),18.0);
    vec3 shallow=mix(vec3(0.18,0.48,0.51),vec3(0.19,0.42,0.48),wet.g);
    ALBEDO=mix(shallow,vec3(0.075,0.26,0.37),absorption)
        +relief_amount*(0.11*glint+0.07*(1.0-amount)*(1.0-absorption));
    ALPHA=amount*mix(0.83,mix(0.48,0.92,absorption),relief_amount);
}
