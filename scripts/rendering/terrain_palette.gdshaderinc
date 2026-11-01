// Authored surfaces: colour is sampled directly; black/white masks control coverage.
uniform bool paint_enabled = false;
uniform sampler2DArray paint_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray paint_normals : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray paint_coverage : filter_linear_mipmap, repeat_enable;
uniform sampler2D paint_options : filter_nearest, repeat_disable;
uniform sampler2D paint_biomes : filter_nearest, repeat_disable;

mat2 paint_rotation(float angle) {
	return mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
}

uniform bool ground_paint_enabled = false;
uniform sampler2D ground_paint : filter_linear, repeat_disable;

void paint_selected_row(float row, vec2 position, int selected, out vec3 color, out vec3 gradient, out float roughness) {
	vec3 scores = vec3(-1000.0);
	for (int slot = 0; slot < 3; slot++) {
		vec4 option = texelFetch(paint_options, ivec2(slot, int(row)), 0);
		if (option.b > 0.0) {
			vec2 uv = paint_rotation(option.g) * (position + blend_seed_offset) / option.a;
			uv += vec2(row * 0.137 + float(slot) * 0.31, row * 0.713 + float(slot) * 0.17);
			scores[slot] = texture(paint_coverage, vec3(uv, row * 3.0 + float(slot))).r + log(max(option.b, 0.0001)) * 0.14;
		}
	}
	if (selected >= 0) { scores = vec3(-1000.0); scores[selected] = 1.0; }
	float best = max(scores.r, max(scores.g, scores.b));
	// Only a narrow contact band mixes surfaces; most patches contain one texture.
	float feather = 0.10 + min(fwidth(best), 0.15);
	vec3 weights = smoothstep(vec3(best - feather), vec3(best), scores);
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	color = vec3(0.0);
	gradient = vec3(0.0);
	roughness = 0.0;
	for (int slot = 0; slot < 3; slot++) {
		if (weights[slot] > 0.0001) {
			vec4 option = texelFetch(paint_options, ivec2(slot, int(row)), 0);
			mat2 rotation = paint_rotation(option.g);
			vec2 uv = rotation * position / option.r;
			float layer = row * 3.0 + float(slot);
			vec4 diffuse = texture(paint_albedo, vec3(uv, layer));
			vec4 encoded = texture(paint_normals, vec3(uv, layer));
			vec3 n = encoded.rgb * 2.0 - 1.0;
			vec2 local_gradient = transpose(rotation) * (n.xy / max(n.z, 0.25));
			color += diffuse.rgb * weights[slot];
			gradient += vec3(local_gradient.x, 0.0, local_gradient.y) * weights[slot];
			roughness += encoded.a * weights[slot];
		}
	}
}

void paint_row(float row, vec2 position, out vec3 color, out vec3 gradient, out float roughness) {
	paint_selected_row(row, position, -1, color, gradient, roughness);
}

float paint_biome(vec2 climate) {
	vec2 size = vec2(textureSize(paint_biomes, 0));
	vec2 uv = (clamp(climate, vec2(0.0), vec2(1.0)) * (size - vec2(1.0)) + vec2(0.5)) / size;
	return floor(texture(paint_biomes, uv).r * 255.0 + 0.5);
}

void painted_surface(vec3 position, vec3 macro, vec2 climate, vec4 habitat, float beach, float wet, float rock, float snow, float detail, vec2 map_extent, vec4 coverage_signals, out vec3 color, out vec3 normal, out float roughness) {
	vec3 gradient;
	paint_row(paint_biome(climate), position.xz, color, gradient, roughness);
	// Per-pixel climate boundary coverage: preserve texture colours and antialias the edge.
	vec2 footprint = abs(dFdx(climate)) + abs(dFdy(climate));
	float neighbor = paint_biome(climate + footprint * 0.5);
	float other = paint_biome(climate - footprint * 0.5);
	vec3 c;
	vec3 g;
	float r;
	if (neighbor != paint_biome(climate)) {
		paint_row(neighbor, position.xz, c, g, r);
		color = mix(color, c, 0.25); gradient = mix(gradient, g, 0.25); roughness = mix(roughness, r, 0.25);
	}
	if (other != paint_biome(climate)) {
		paint_row(other, position.xz, c, g, r);
		color = mix(color, c, 0.25); gradient = mix(gradient, g, 0.25); roughness = mix(roughness, r, 0.25);
	}
	// Water-fed habitats and overlays use the same authored surface pipeline.
	for (int overlay = 0; overlay < 6; overlay++) {
		float row = 18.0;
		float mask = wet * 0.45;
		if (overlay == 1) { row = 13.0; mask = habitat.g; }
		if (overlay == 2) { row = 14.0; mask = habitat.b; }
		if (overlay == 3) { row = 15.0; mask = beach; }
		if (overlay == 4) { row = 16.0; mask = rock; }
		if (overlay == 5) { row = 17.0; mask = snow; }
		if (mask > 0.001) {
			paint_row(row, position.xz, c, g, r);
			if (overlay == 4) {
				vec3 axis = pow(abs(macro), vec3(4.0));
				axis /= max(dot(axis, vec3(1.0)), 0.0001);
				c *= axis.y; g *= axis.y; r *= axis.y;
				vec3 cx; vec3 gx; float rx;
				paint_row(row, position.yz, cx, gx, rx);
				c += cx * axis.x; g += vec3(0.0, gx.x, gx.z) * axis.x; r += rx * axis.x;
				paint_row(row, position.xy, cx, gx, rx);
				c += cx * axis.z; g += vec3(gx.x, gx.z, 0.0) * axis.z; r += rx * axis.z;
			}
			color = mix(color, c, mask); gradient = mix(gradient, g, mask); roughness = mix(roughness, r, mask);
		}
	}
	if (ground_paint_enabled) {
		vec2 size = vec2(textureSize(ground_paint, 0));
		vec2 point = clamp(position.xz / map_extent + vec2(0.5), vec2(0.0), vec2(1.0)) * (size - vec2(1.0));
		ivec2 cell = ivec2(floor(point + vec2(0.5)));
		vec4 brush = texelFetch(ground_paint, cell, 0);
		if (brush.g > 0.001) {
			paint_selected_row(floor(brush.r * 255.0 + 0.5), position.xz, int(floor(brush.b * 255.0 + 0.5)) - 1, c, g, r);
			float strength = texture(ground_paint, (point + vec2(0.5)) / size).g;
			int selected = int(floor(brush.b * 255.0 + 0.5)) - 1;
			if (selected >= 0) {
				float row = floor(brush.r * 255.0 + 0.5);
				vec4 option = texelFetch(paint_options, ivec2(selected, int(row)), 0);
				vec2 uv = paint_rotation(option.g) * (position.xz + blend_seed_offset) / option.a;
				uv += vec2(row * 0.137 + float(selected) * 0.31, row * 0.713 + float(selected) * 0.17);
				strength *= smoothstep(0.22, 0.65, texture(paint_coverage, vec3(uv, row * 3.0 + float(selected))).r);
			}
			float coverage = mix(strength, terrain_patch_edge(strength, coverage_signals.a), clamp(strength * 2.0, 0.0, 1.0));
			color = mix(color, c, coverage); gradient = mix(gradient, g, coverage); roughness = mix(roughness, r, coverage);
		}
	}
	gradient -= macro * dot(gradient, macro);
	normal = normalize(macro + gradient * detail * 0.65);
}
