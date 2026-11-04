shader_type spatial;
render_mode unshaded, cull_back;
#include "res://scripts/rendering/map_relief.gdshaderinc"
uniform float tree_detail = 1.0;
varying vec3 tree_normal;
varying vec3 tree_color;
varying float tree_variation;
void vertex() {
    tree_color = COLOR.rgb;
    float local_height = VERTEX.y;
    tree_variation = INSTANCE_CUSTOM.a;
    float sway = sin(TIME*1.1+INSTANCE_CUSTOM.x*94.0+INSTANCE_CUSTOM.y*57.0)*0.015;
    VERTEX.x += sway*local_height*local_height;
    VERTEX.y += relief_height(INSTANCE_CUSTOM.xy)/INSTANCE_CUSTOM.z;
    tree_normal = normalize(mat3(MODEL_MATRIX)*NORMAL);
}
void fragment() {
    // Opaque screen-door fade avoids sorting overlapping transparent crowns.
    float threshold = fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))));
    if (tree_detail <= threshold) discard;
    float light = 0.55+0.45*max(dot(normalize(tree_normal),normalize(vec3(-0.6,0.8,-0.4))),0.0);
    ALBEDO = tree_color*light*mix(0.8,1.08,tree_variation);
}
