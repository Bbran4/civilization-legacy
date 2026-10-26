shader_type spatial;
render_mode diffuse_burley;
uniform vec2 map_size = vec2(1024.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool has_albedo_texture = false;
uniform float tree_roughness = 0.95;
uniform float alpha_cutoff = 0.35;
uniform float vegetation_fade = 1.0;
uniform mat4 world_to_terrain = mat4(1.0);
#include "res://scripts/rendering/terrain_height_sampling.gdshaderinc"
varying vec3 tree_color;
void vertex() {
	// Instance transforms retain root precision on large maps; packed custom colour data does not.
	mat4 instance_to_terrain = world_to_terrain * MODEL_MATRIX;
	vec3 root = instance_to_terrain[3].xyz;
	float instance_scale = length(instance_to_terrain[1].xyz);
	VERTEX.y += (displayed_height(root.xz) - 0.015 - root.y) / max(instance_scale, 0.001);
	tree_color = COLOR.rgb;
}
void fragment() {
	float threshold = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (vegetation_fade < 0.999 && threshold > vegetation_fade) { discard; }
	vec4 texel = has_albedo_texture ? texture(albedo_texture, UV) : vec4(1.0);
	if (texel.a < alpha_cutoff) { discard; }
	ALBEDO = tree_color * texel.rgb;
	ROUGHNESS = tree_roughness;
	SPECULAR = 0.12;
}
