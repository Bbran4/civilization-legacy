shader_type spatial;
render_mode diffuse_burley;

uniform vec2 map_size = vec2(192.0, 144.0);
uniform float sea_level = 0.0;
uniform float height_scale = 34.0;
uniform float height_offset = -6.0;
uniform float overview_blend = 0.0;
uniform bool terrain_lod = false;
uniform float lod_blend = 1.0;
uniform bool heightmap_view = false;
uniform bool macro_normals_enabled = false;
uniform sampler2D macro_normal_field : filter_linear_mipmap, repeat_disable;
uniform float beach_width = 2.0;
uniform float rock_slope = 0.32;
uniform float snow_height = 18.0;
uniform vec4 sand_color : source_color = vec4(0.78, 0.72, 0.5, 1.0);
uniform vec4 grass_color : source_color = vec4(0.43, 0.54, 0.32, 1.0);
uniform vec4 rock_color : source_color = vec4(0.47, 0.48, 0.45, 1.0);
uniform vec4 snow_color : source_color = vec4(0.89, 0.9, 0.86, 1.0);
#include "res://scripts/rendering/climate.gdshaderinc"
#include "res://scripts/rendering/terrain_surface.gdshaderinc"

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
	terrain_position = VERTEX;
	terrain_normal = NORMAL;
	terrain_to_view = mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX;
}

void fragment() {
	float altitude = terrain_position.y - sea_level;
	float slope = 1.0 - clamp(normalize(terrain_normal).y, 0.0, 1.0);
	vec2 uv = terrain_position.xz / map_size;
	float variation = smooth_noise(uv * 12.0) * 0.6 + smooth_noise(uv * 32.0) * 0.28 + smooth_noise(uv * 92.0) * 0.12;
	float pixel_span = max(length(dFdx(terrain_position.xz)), length(dFdy(terrain_position.xz)));
	bool diagnostic = climate_mode > 0 || heightmap_view;
	float material_detail = diagnostic ? 0.0 : (1.0 - smoothstep(0.04, 0.4, pixel_span)) * (1.0 - overview_blend);
	vec4 local_climate = texture(climate_field, uv + vec2(0.5));
	// Classify the continuously sampled climate through the domain-owned palette,
	// rather than magnifying a blurred, low-resolution map of biome colours.
	vec4 habitat = habitats_enabled ? texture(habitat_field, uv + vec2(0.5)) : vec4(0.0);
	float demand = max(150.0, 400.0 + 45.0 * max(-5.0, local_climate.r * 140.0 - 80.0));
	vec2 ecological_climate = vec2(local_climate.r, local_climate.g + habitat.r * demand * 1.2 / 6000.0);
	vec2 palette_size = vec2(textureSize(biome_palette, 0));
	vec2 palette_uv = (clamp(ecological_climate, vec2(0.0), vec2(1.0)) * (palette_size - vec2(1.0)) + vec2(0.5)) / palette_size;
	vec3 cover_color = biomes_enabled ? texture(biome_palette, palette_uv).rgb : grass_color.rgb;
	cover_color = mix(cover_color, vec3(0.4, 0.52, 0.41), habitat.g);
	cover_color = mix(cover_color, vec3(0.294, 0.502, 0.333), habitat.b);
	vec3 grass = cover_color * mix(0.94, 1.06, variation);
	vec3 color = mix(sand_color.rgb, grass, smoothstep(0.2, beach_width, altitude));
	float rock = max(smoothstep(rock_slope, min(rock_slope + 0.25, 1.0), slope), smoothstep(height_scale * 0.55, height_scale * 0.8, altitude));
	color = mix(color, rock_color.rgb, rock);
	float temperature_c = local_climate.r * 140.0 - 80.0;
	float snow = biomes_enabled ? 1.0 - smoothstep(-10.0, 0.0, temperature_c) : smoothstep(snow_height, snow_height + 3.0, altitude + variation);
	snow *= 1.0 - smoothstep(0.4, 0.75, slope);
	color = mix(color, snow_color.rgb, snow);
	vec3 material_tint;
	vec3 detail_normal;
	float material_roughness;
	vec4 ground_weights = surface_materials_enabled ? texture(surface_weights, palette_uv) : vec4(1.0, 0.0, 0.0, 0.0);
	ground_weights = mix(ground_weights, vec4(0.3, 0.05, 0.65, 0.0), habitat.a * 0.35);
	float beach = 1.0 - smoothstep(0.2, beach_width, altitude);
	ground_weights = mix(ground_weights, vec4(0.0, 0.0, 0.0, 1.0), beach);
	float wet = clamp(max(habitat.g, habitat.r * 0.45) * (1.0 - rock), 0.0, 1.0);
	vec3 macro_normal = macro_normals_enabled ? normalize(texture(macro_normal_field, uv + vec2(0.5)).rgb * 2.0 - 1.0) : normalize(terrain_normal);
	layered_surface(terrain_position, macro_normal, ground_weights, wet, rock, snow, material_detail, material_tint, detail_normal, material_roughness);
	if (surface_materials_enabled) {
		color *= texture(regional_tint, uv + vec2(0.5)).rgb * material_tint;
	}
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
