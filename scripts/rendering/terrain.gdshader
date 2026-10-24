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
uniform float beach_width = 2.0;
uniform float rock_slope = 0.32;
uniform float snow_height = 18.0;
uniform vec4 sand_color : source_color = vec4(0.78, 0.72, 0.5, 1.0);
uniform vec4 grass_color : source_color = vec4(0.43, 0.54, 0.32, 1.0);
uniform vec4 rock_color : source_color = vec4(0.47, 0.48, 0.45, 1.0);
uniform vec4 snow_color : source_color = vec4(0.89, 0.9, 0.86, 1.0);
#include "res://scripts/rendering/climate.gdshaderinc"

varying vec3 terrain_position;
varying vec3 terrain_normal;

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
}

void fragment() {
	float altitude = terrain_position.y - sea_level;
	float slope = 1.0 - clamp(normalize(terrain_normal).y, 0.0, 1.0);
	vec2 uv = terrain_position.xz / map_size;
	float variation = smooth_noise(uv * 12.0) * 0.6 + smooth_noise(uv * 32.0) * 0.28 + smooth_noise(uv * 92.0) * 0.12;
	float pixel_span = max(length(dFdx(terrain_position.xz)), length(dFdy(terrain_position.xz)));
	float fine_weight = 1.0 - smoothstep(0.1, 1.0, pixel_span);
	float fine = smooth_noise(terrain_position.xz * 0.7) * 0.6 + smooth_noise(terrain_position.xz * 2.1) * 0.4;
	vec4 local_climate = texture(climate_field, uv + vec2(0.5));
	// Classify the continuously sampled climate through the domain-owned palette,
	// rather than magnifying a blurred, low-resolution map of biome colours.
	vec2 palette_size = vec2(textureSize(biome_palette, 0));
	vec2 palette_uv = (clamp(local_climate.rg, vec2(0.0), vec2(1.0)) * (palette_size - vec2(1.0)) + vec2(0.5)) / palette_size;
	vec3 cover_color = biomes_enabled ? texture(biome_palette, palette_uv).rgb : grass_color.rgb;
	vec3 grass = cover_color * mix(0.94, 1.06, variation) * mix(1.0, mix(0.93, 1.07, fine), fine_weight);
	vec3 color = mix(sand_color.rgb, grass, smoothstep(0.2, beach_width, altitude));
	float rock = max(smoothstep(rock_slope, min(rock_slope + 0.25, 1.0), slope), smoothstep(height_scale * 0.55, height_scale * 0.8, altitude));
	color = mix(color, rock_color.rgb * mix(1.0, mix(0.85, 1.12, fine), fine_weight), rock);
	float temperature_c = local_climate.r * 140.0 - 80.0;
	float snow = biomes_enabled ? 1.0 - smoothstep(-10.0, 0.0, temperature_c) : smoothstep(snow_height, snow_height + 3.0, altitude + variation);
	color = mix(color, snow_color.rgb, snow * (1.0 - smoothstep(0.4, 0.75, slope)));
	if (climate_mode > 0) {
		color = climate_color(uv + vec2(0.5));
	}
	float climate_flatness = climate_mode > 0 ? 1.0 : overview_blend;
	ALBEDO = color * (1.0 - climate_flatness);
	EMISSION = color * climate_flatness;
	SPECULAR = 0.5 * (1.0 - overview_blend);
	if (heightmap_view) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(clamp((terrain_position.y - height_offset) / height_scale, 0.0, 1.0));
	}
	ROUGHNESS = 0.94;
}
