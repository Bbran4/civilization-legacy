// Seeded, world-space appearance masks. Native biome and climate data stay unchanged.
uniform sampler2D transition_noise : filter_linear_mipmap_anisotropic, repeat_enable;
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
		vec4 medium = texture(transition_noise, rotated / 32.0 + vec2(0.17, 0.43));
		vec4 fine = texture(transition_noise, p / 8.0 + vec2(0.61, 0.29));
		float broad_visibility = 1.0 - smoothstep(8.0, 30.0, pixel_span);
		float medium_visibility = 1.0 - smoothstep(1.5, 6.0, pixel_span);
		float fine_visibility = 1.0 - smoothstep(0.3, 1.5, pixel_span);
		signals += (broad - vec4(0.5)) * 0.55 * broad_visibility;
		signals += (medium - vec4(0.5)) * 0.35 * medium_visibility;
		signals += (fine - vec4(0.5)) * 0.10 * fine_visibility;
		// Broad, high-contrast coverage shapes; small noise only breaks their edges.
		signals = clamp(vec4(0.5) + (signals - vec4(0.5)) * 3.0, vec4(0.0), vec4(1.0));
	}
}

vec4 terrain_patch_weights(vec4 weights, vec4 signals) {
	vec4 result = weights * exp2((signals - vec4(0.5)) * 12.0);
	return result / max(dot(result, vec4(1.0)), 0.0001);
}

float terrain_patch_edge(float mask, float signal) {
	if (!terrain_blending_enabled || !surface_materials_enabled) { return mask; }
	// The material owns coverage, not just tint. Keep pure interiors and break up contacts.
	float coverage = mask + (signal - 0.5) * 1.4 * (4.0 * mask * (1.0 - mask));
	return smoothstep(0.28, 0.72, coverage);
}

vec4 terrain_habitat(vec2 uv, vec2 extent) {
	// Prefilter categorical wetland/woodland coverage in a fixed ten-unit footprint.
	// Interpolated mip levels remove the cell edge before the noisy coverage threshold.
	vec2 texels_per_unit = vec2(textureSize(habitat_field, 0)) / extent;
	float level = max(0.0, log2(max(texels_per_unit.x, texels_per_unit.y) * 10.0));
	return textureLod(habitat_field, uv, level);
}
