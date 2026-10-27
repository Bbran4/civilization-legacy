// Seeded, world-space appearance masks. Native biome and climate data stay unchanged.
uniform sampler2D transition_noise : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D transition_colors : source_color, filter_linear, repeat_disable;
uniform sampler2D transition_weights : filter_linear, repeat_disable;
uniform bool terrain_blending_enabled = true;
uniform vec2 blend_seed_offset = vec2(0.0);

void terrain_blend_data(vec2 position, float pixel_span, out vec2 warp, out vec4 signals) {
	warp = vec2(0.0);
	signals = vec4(0.5);
	if (terrain_blending_enabled && surface_materials_enabled) {
		vec2 p = position + blend_seed_offset;
		// The low-frequency warp has a fixed sampling level: zoom never relocates patches.
		vec4 broad = textureLod(transition_noise, p / 128.0, 0.0);
		warp = (broad.gb - vec2(0.5)) * 4.0;
		p += warp;
		vec2 rotated = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
		vec4 medium = texture(transition_noise, rotated / 24.0 + vec2(0.17, 0.43));
		vec4 fine = texture(transition_noise, p / 6.0 + vec2(0.61, 0.29));
		float broad_visibility = 1.0 - smoothstep(8.0, 30.0, pixel_span);
		float medium_visibility = 1.0 - smoothstep(1.5, 6.0, pixel_span);
		float fine_visibility = 1.0 - smoothstep(0.3, 1.5, pixel_span);
		signals += (broad - vec4(0.5)) * 0.38 * broad_visibility;
		signals += (medium - vec4(0.5)) * 0.46 * medium_visibility;
		signals += (fine - vec4(0.5)) * 0.16 * fine_visibility;
	}
}

vec4 terrain_patch_weights(vec4 weights, vec4 signals) {
	vec4 result = weights * exp2((signals - vec4(0.5)) * 7.0);
	return result / max(dot(result, vec4(1.0)), 0.0001);
}

float terrain_patch_edge(float mask, float signal) {
	if (!terrain_blending_enabled || !surface_materials_enabled) { return mask; }
	// Only the contact zone changes; pure interiors retain their material.
	return clamp(mask + (signal - 0.5) * 1.5 * (4.0 * mask * (1.0 - mask)), 0.0, 1.0);
}

vec3 terrain_pigment(vec4 weights) {
	return vec3(0.85, 1.05, 0.85) * weights.r + vec3(1.12, 1.0, 0.78) * weights.g + vec3(1.12, 0.79, 0.57) * weights.b + vec3(1.10, 1.05, 0.91) * weights.a;
}

vec3 terrain_patch_tint(vec4 weights, vec4 reference, float wet, float rock, float snow) {
	if (!terrain_blending_enabled || !surface_materials_enabled) { return vec3(1.0); }
	vec3 ratio = terrain_pigment(weights) / max(terrain_pigment(reference), vec3(0.01));
	return mix(vec3(1.0), ratio, (1.0 - rock) * (1.0 - snow) * (1.0 - wet * 0.6));
}
