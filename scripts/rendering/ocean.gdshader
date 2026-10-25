shader_type spatial;
render_mode unshaded;

uniform sampler2D height_field : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(1024.0);
uniform bool heightmap_view = false;
uniform float water_height = 0.2;
uniform vec4 water_color : source_color = vec4(0.157, 0.357, 0.439, 1.0);
#include "res://scripts/rendering/climate.gdshaderinc"

varying vec2 map_uv;

void vertex() {
	map_uv = VERTEX.xz / map_size + vec2(0.5);
}

void fragment() {
	if (hydrology_enabled && !heightmap_view && all(greaterThanEqual(map_uv, vec2(0.0))) && all(lessThanEqual(map_uv, vec2(1.0))) && texture(drainage_field, map_uv).a < 0.5) {
		discard;
	}
	float ground = texture(height_field, clamp(map_uv, vec2(0.0), vec2(1.0))).r;
	float depth = max(0.0, water_height - ground);
	float offshore = smoothstep(0.0, 0.16, depth);
	if (any(lessThan(map_uv, vec2(0.0))) || any(greaterThan(map_uv, vec2(1.0)))) {
		offshore = 1.0;
		ground = 0.0;
	}
	vec3 shallow = mix(water_color.rgb, vec3(0.23, 0.55, 0.59), 0.60);
	vec3 deep = water_color.rgb * vec3(0.60, 0.72, 0.82);
	ALBEDO = mix(shallow, deep, offshore);
	if (climate_mode > 0 && all(greaterThanEqual(map_uv, vec2(0.0))) && all(lessThanEqual(map_uv, vec2(1.0)))) {
		ALBEDO = climate_color(map_uv);
	}
	if (heightmap_view) {
		ALBEDO = vec3(clamp(ground, 0.0, 1.0));
	}
	ROUGHNESS = 1.0;
}
