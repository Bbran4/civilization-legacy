shader_type spatial;
render_mode diffuse_burley;

uniform vec2 map_size = vec2(192.0, 144.0);
uniform float sea_level = 0.0;
uniform float height_scale = 34.0;
uniform float height_offset = -6.0;
uniform float overview_blend = 0.0;
uniform bool flat_map_mode = true;
uniform bool provinces_enabled = false;
uniform sampler2D province_field : filter_nearest_mipmap, repeat_disable;
uniform bool terrain_lod = false;
uniform float lod_blend = 1.0;
uniform bool heightmap_view = false;
uniform bool macro_normals_enabled = false;
uniform sampler2D macro_normal_field : filter_linear_mipmap, repeat_disable;
uniform float beach_width = 2.0;
uniform vec3 overview_light_direction = vec3(-0.2868, 0.8192, 0.4967);
uniform float rock_slope = 0.32;
uniform float snow_height = 18.0;
uniform vec4 sand_color : source_color = vec4(0.78, 0.72, 0.5, 1.0);
uniform vec4 grass_color : source_color = vec4(0.43, 0.54, 0.32, 1.0);
uniform vec4 rock_color : source_color = vec4(0.47, 0.48, 0.45, 1.0);
uniform vec4 snow_color : source_color = vec4(0.89, 0.9, 0.86, 1.0);
#include "res://scripts/rendering/climate.gdshaderinc"
#include "res://scripts/rendering/terrain_surface.gdshaderinc"
#include "res://scripts/rendering/terrain_palette.gdshaderinc"

varying vec3 terrain_position;
varying vec3 terrain_normal;
varying mat3 terrain_to_view;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	if (terrain_lod) {
		VERTEX.y = mix(UV2.x, VERTEX.y, lod_blend);
		NORMAL = normalize(mix(COLOR.rgb * 2.0 - 1.0, NORMAL, lod_blend));
	}
	// Keep the generated elevation available to the fragment shader for biome,
	// mountain and water classification, while presenting land as a flat map.
	vec3 source_position = VERTEX;
	if (flat_map_mode) {
		VERTEX.y = max(VERTEX.y, sea_level + 0.02);
	}
	terrain_position = source_position;
	terrain_normal = NORMAL;
	terrain_to_view = mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX;
}

void fragment() {
	float altitude = terrain_position.y - sea_level;
	vec2 normal_size = vec2(textureSize(macro_normal_field, 0));
	vec2 normal_uv = (clamp(terrain_position.xz / map_size + vec2(0.5), vec2(0.0), vec2(1.0)) * (normal_size - vec2(1.0)) + vec2(0.5)) / normal_size;
	vec4 relief_sample = macro_normals_enabled ? texture(macro_normal_field, normal_uv) : vec4(normalize(terrain_normal) * 0.5 + 0.5, 1.0);
	vec3 macro_normal = normalize(relief_sample.rgb * 2.0 - 1.0);
	float slope = 1.0 - clamp(macro_normal.y, 0.0, 1.0);
	vec2 uv = terrain_position.xz / map_size;
	float variation = smooth_noise(uv * 12.0) * 0.6 + smooth_noise(uv * 32.0) * 0.28 + smooth_noise(uv * 92.0) * 0.12;
	float pixel_span = max(length(dFdx(terrain_position.xz)), length(dFdy(terrain_position.xz)));
	bool diagnostic = climate_mode > 0 || heightmap_view;
	float material_detail = diagnostic ? 0.0 : (1.0 - smoothstep(0.04, 0.4, pixel_span)) * (1.0 - overview_blend);
	vec2 blend_warp;
	vec4 blend_signals;
	terrain_blend_data(terrain_position.xz, pixel_span, blend_warp, blend_signals);
	if (terrain_blending_enabled && surface_materials_enabled) { variation = blend_signals.g; }
	vec2 appearance_uv = clamp(uv + vec2(0.5) + blend_warp / map_size, vec2(0.0), vec2(1.0));
	vec4 local_climate = texture(climate_field, uv + vec2(0.5));
	vec4 appearance_climate = texture(climate_field, appearance_uv);
	// Classify the continuously sampled climate through the domain-owned palette,
	// rather than magnifying a blurred, low-resolution map of biome colours.
	bool ecotone = terrain_blending_enabled && surface_materials_enabled;
	vec4 habitat = habitats_enabled ? (ecotone ? terrain_habitat(appearance_uv, map_size) : texture(habitat_field, appearance_uv)) : vec4(0.0);
	// Water-fed colour overlays used to bypass the material masks entirely.
	habitat.g = terrain_patch_edge(habitat.g, blend_signals.g);
	habitat.b = terrain_patch_edge(habitat.b, blend_signals.r);
	float growing = smoothstep(0.0, 4.0, appearance_climate.r * 140.0 - 80.0);
	habitat.gb *= growing;
	float demand = max(150.0, 400.0 + 45.0 * max(-5.0, appearance_climate.r * 140.0 - 80.0));
	vec2 ecological_climate = vec2(appearance_climate.r + (blend_signals.a - 0.5) * 8.0 / 140.0, appearance_climate.g + habitat.r * demand * 1.2 / 6000.0 + (blend_signals.r - 0.5) * 1000.0 / 6000.0);
	vec2 palette_size = vec2(textureSize(biome_palette, 0));
	vec2 palette_uv = (clamp(ecological_climate, vec2(0.0), vec2(1.0)) * (palette_size - vec2(1.0)) + vec2(0.5)) / palette_size;
	vec3 cover_color = biomes_enabled ? texture(biome_palette, palette_uv).rgb : grass_color.rgb;
	cover_color = mix(cover_color, vec3(0.4, 0.52, 0.41), habitat.g);
	cover_color = mix(cover_color, vec3(0.294, 0.502, 0.333), habitat.b);
	vec3 grass = cover_color * mix(0.94, 1.06, variation);
	// A wider coverage zone admits sand/vegetation islands; the waterline stays sand.
	float beach_extent = ecotone ? beach_width * 1.8 : beach_width;
	float beach = terrain_patch_edge(1.0 - smoothstep(0.2, beach_extent, altitude), blend_signals.a);
	vec3 color = mix(grass, sand_color.rgb, beach);
	if (provinces_enabled && flat_map_mode) {
		vec2 province_uv = clamp(uv + vec2(0.5), vec2(0.0), vec2(1.0));
		vec4 province = texture(province_field, province_uv);
		vec2 texel = 1.0 / vec2(textureSize(province_field, 0));
		float edge = 0.0;
		edge = max(edge, step(0.015, distance(province.rgb, texture(province_field, province_uv + vec2(texel.x, 0.0)).rgb)));
		edge = max(edge, step(0.015, distance(province.rgb, texture(province_field, province_uv + vec2(0.0, texel.y)).rgb)));
		edge = max(edge, step(0.015, distance(province.rgb, texture(province_field, province_uv - vec2(texel.x, 0.0)).rgb)));
		edge = max(edge, step(0.015, distance(province.rgb, texture(province_field, province_uv - vec2(0.0, texel.y)).rgb)));
		color = province.a > 0.5 ? mix(color, province.rgb, 0.38) : color;
		color = mix(color, vec3(0.12, 0.10, 0.08), edge * province.a * 0.8);
	}
	float rock = max(smoothstep(rock_slope, min(rock_slope + 0.25, 1.0), slope), smoothstep(height_scale * 0.55, height_scale * 0.8, altitude));
	float highland = smoothstep(height_scale * 0.28, height_scale * 0.62, altitude);
	rock = max(rock, highland * mix(0.65, 1.0, smoothstep(0.05, 0.28, slope)));
	rock = terrain_patch_edge(rock, blend_signals.b);
	color = mix(color, rock_color.rgb, rock);
	float temperature_c = local_climate.r * 140.0 - 80.0;
	float snow = biomes_enabled ? 1.0 - smoothstep(-10.0, 0.0, temperature_c) : smoothstep(snow_height, snow_height + 3.0, altitude + variation);
	snow *= 1.0 - smoothstep(0.10, 0.42, slope);
	snow = terrain_patch_edge(snow, blend_signals.g);
	// Leave lighting headroom so bright snow retains ridge shading in Compatibility.
	color = mix(color, snow_color.rgb * 0.78, snow);
	vec3 material_tint;
	vec3 detail_normal;
	float material_roughness;
	vec4 ground_weights = surface_materials_enabled ? texture(surface_weights, palette_uv) : vec4(1.0, 0.0, 0.0, 0.0);
	ground_weights = mix(ground_weights, vec4(0.3, 0.05, 0.65, 0.0), habitat.a * 0.35);
	ground_weights = mix(ground_weights, vec4(0.0, 0.0, 0.0, 1.0), beach);
	float wet = terrain_patch_edge(clamp(max(habitat.g, habitat.r * 0.45) * (1.0 - rock), 0.0, 1.0), blend_signals.b);
	ground_weights /= max(dot(ground_weights, vec4(1.0)), 0.0001);
	vec4 patch_weights = terrain_patch_weights(ground_weights, blend_signals);

	if (paint_enabled && surface_materials_enabled) {
		painted_surface(terrain_position, macro_normal, ecological_climate, habitat, beach, wet, rock, snow, material_detail, map_size, blend_signals, color, detail_normal, material_roughness);
	} else {
		layered_surface(terrain_position, macro_normal, ground_weights, patch_weights, wet, rock, snow, material_detail, material_tint, detail_normal, material_roughness);
		if (surface_materials_enabled) { color *= material_tint; }
	}
	color *= mix(1.0, relief_sample.a, highland);
	float hillshade = mix(0.58, 1.12, max(0.0, dot(macro_normal, normalize(overview_light_direction))));
	color *= mix(1.0, hillshade, overview_blend * highland);
	NORMAL = normalize(terrain_to_view * detail_normal);
	if (climate_mode > 0) {
		color = climate_color(uv + vec2(0.5));
	}
	float climate_flatness = climate_mode > 0 ? 1.0 : overview_blend;
	ALBEDO = color * (1.0 - climate_flatness);
	EMISSION = color * climate_flatness;
	SPECULAR = diagnostic ? 0.0 : 0.25 * (1.0 - overview_blend);
	if (heightmap_view) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(clamp((terrain_position.y - height_offset) / height_scale, 0.0, 1.0));
	}
	ROUGHNESS = climate_mode > 0 || heightmap_view ? 1.0 : material_roughness;
}
