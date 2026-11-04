shader_type spatial;
render_mode cull_back, ambient_light_disabled, specular_disabled, fog_disabled;
#include "res://scripts/rendering/map_relief.gdshaderinc"
#include "res://scripts/rendering/map_lighting.gdshaderinc"
uniform float tree_detail = 1.0;
uniform float max_height_factor = 1.25;
uniform float max_width_factor = 1.15;
uniform float bend_amount = 0.035;
uniform float wind_amount = 0.015;
varying vec3 tree_normal;
varying vec3 tree_color;
varying float tree_variation;
varying vec3 tree_world_position;
void vertex() {
    tree_color = COLOR.rgb;
    float local_height = VERTEX.y;
    tree_variation = INSTANCE_CUSTOM.a;
    float height_factor = mix(0.82,max_height_factor,tree_variation);
    float width_factor = mix(0.86,max_width_factor,fract(tree_variation*19.73));
    VERTEX.xz *= width_factor;
    VERTEX.y *= height_factor;
    float sway = sin(TIME*1.1+INSTANCE_CUSTOM.x*94.0+INSTANCE_CUSTOM.y*57.0)*wind_amount;
    float lean = sin(tree_variation*64.0)*bend_amount;
    VERTEX.x += (lean+sway)*local_height*local_height;
    VERTEX.y += relief_height(INSTANCE_CUSTOM.xy)/INSTANCE_CUSTOM.z;
    NORMAL = normalize(vec3(NORMAL.x/width_factor,NORMAL.y/height_factor,NORMAL.z/width_factor));
    tree_normal = normalize(mat3(MODEL_MATRIX)*NORMAL);
    tree_world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
    // Opaque screen-door fade avoids sorting overlapping transparent crowns.
    float threshold = fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))));
    if (tree_detail <= threshold) discard;
    ALBEDO = map_haze(tree_color*map_light(normalize(tree_normal))*mix(0.8,1.08,tree_variation),tree_world_position,relief_amount);
    EMISSION = ALBEDO*(1.0-map_shadow_strength*relief_amount);
}
void light() {
    if (LIGHT_IS_DIRECTIONAL) DIFFUSE_LIGHT += vec3(map_shadow_strength*relief_amount*ATTENUATION);
}
