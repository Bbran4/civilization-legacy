// Colour array is sRGB; packed normal/roughness, weights and regional multipliers are numeric.
uniform sampler2DArray surface_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surface_normals : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_weights : filter_linear, repeat_disable;
uniform sampler2D regional_tint : filter_linear, repeat_disable;
uniform bool surface_materials_enabled = false;
uniform float surface_tile_size = 8.0;
#include "res://scripts/rendering/terrain_blending.gdshaderinc"

vec3 surface_gradient(vec4 encoded) {
	vec3 n = encoded.rgb * 2.0 - 1.0;
	return vec3(n.x, 0.0, n.y) / max(n.z, 0.25);
}

void layered_surface(vec3 p, vec3 macro_normal, vec4 ground, vec4 patches, float wet, float rock, float snow, float detail, out vec3 tint, out vec3 perturbed, out float roughness) {
	tint = terrain_patch_tint(patches, ground, wet, rock, snow);
	perturbed = macro_normal;
	roughness = 0.94;
	if (surface_materials_enabled && detail > 0.001) {
		// Compatibility samples display-space colours; Forward+ samples linear colours.
		float neutral = OUTPUT_IS_SRGB ? 0.73535698 : 0.5;
		vec2 tile = p.xz / surface_tile_size;
		vec4 g0 = texture(surface_albedo, vec3(tile, 0.0));
		vec4 g1 = texture(surface_albedo, vec3(tile, 1.0));
		vec4 g2 = texture(surface_albedo, vec3(tile, 2.0));
		vec4 g3 = texture(surface_albedo, vec3(tile, 3.0));
		// Albedo alpha is micro-height: perturb transitions, then renormalize.
		vec4 w = patches * exp2((vec4(g0.a, g1.a, g2.a, g3.a) - 0.5) * 2.5);
		w /= max(dot(w, vec4(1.0)), 0.0001);
		vec4 n0 = texture(surface_normals, vec3(tile, 0.0));
		vec4 n1 = texture(surface_normals, vec3(tile, 1.0));
		vec4 n2 = texture(surface_normals, vec3(tile, 2.0));
		vec4 n3 = texture(surface_normals, vec3(tile, 3.0));
		vec3 diffuse = (g0.rgb * w.x + g1.rgb * w.y + g2.rgb * w.z + g3.rgb * w.w) / neutral;
		vec3 gradient = surface_gradient(n0) * w.x + surface_gradient(n1) * w.y + surface_gradient(n2) * w.z + surface_gradient(n3) * w.w;
		float r = dot(vec4(n0.a, n1.a, n2.a, n3.a), w);
		vec4 wet_diffuse = texture(surface_albedo, vec3(tile, 6.0));
		vec4 wet_normal = texture(surface_normals, vec3(tile, 6.0));
		diffuse = mix(diffuse, wet_diffuse.rgb * 0.825 / neutral, wet);
		gradient = mix(gradient, surface_gradient(wet_normal), wet);
		r = mix(r, wet_normal.a, wet);
		// Cliff rock uses three projections instead of stretching a top-down tile.
		vec3 axis = pow(abs(macro_normal), vec3(4.0));
		axis /= max(dot(axis, vec3(1.0)), 0.0001);
		vec4 rock_x = texture(surface_albedo, vec3(p.yz / surface_tile_size, 4.0));
		vec4 rock_y = texture(surface_albedo, vec3(tile, 4.0));
		vec4 rock_z = texture(surface_albedo, vec3(p.xy / surface_tile_size, 4.0));
		vec4 nx = texture(surface_normals, vec3(p.yz / surface_tile_size, 4.0));
		vec4 ny = texture(surface_normals, vec3(tile, 4.0));
		vec4 nz = texture(surface_normals, vec3(p.xy / surface_tile_size, 4.0));
		vec3 gx = surface_gradient(nx);
		vec3 gy = surface_gradient(ny);
		vec3 gz = surface_gradient(nz);
		vec3 rock_gradient = vec3(0.0, gx.x, gx.z) * axis.x + gy * axis.y + vec3(gz.x, gz.z, 0.0) * axis.z;
		diffuse = mix(diffuse, (rock_x.rgb * axis.x + rock_y.rgb * axis.y + rock_z.rgb * axis.z) / neutral, rock);
		gradient = mix(gradient, rock_gradient, rock);
		r = mix(r, dot(vec3(nx.a, ny.a, nz.a), axis), rock);
		vec4 ice_diffuse = texture(surface_albedo, vec3(tile, 5.0));
		vec4 ice_normal = texture(surface_normals, vec3(tile, 5.0));
		diffuse = mix(diffuse, ice_diffuse.rgb / neutral, snow);
		gradient = mix(gradient, surface_gradient(ice_normal), snow);
		r = mix(r, ice_normal.a, snow);
		vec3 pigment = terrain_patch_tint(w, ground, wet, rock, snow);
		tint = mix(tint, pigment * diffuse, detail);
		// All detail gradients are in terrain-local space. Project onto the macro tangent plane.
		gradient -= macro_normal * dot(gradient, macro_normal);
		perturbed = normalize(macro_normal + gradient * detail * 0.65);
		roughness = mix(0.94, r, detail);
	}
}
