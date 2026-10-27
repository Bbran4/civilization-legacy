uniform sampler2D drainage_field : source_color, filter_nearest, repeat_disable;
uniform bool hydrology_enabled = false;
uniform sampler2D biome_palette : source_color, filter_linear, repeat_disable;
uniform bool biomes_enabled = false;
uniform sampler2D climate_field : filter_linear, repeat_disable;
uniform sampler2D habitat_field : filter_linear_mipmap, repeat_disable;
uniform sampler2D biome_field : source_color, filter_nearest, repeat_disable;
uniform bool habitats_enabled = false;
uniform int climate_mode = 0;

vec3 climate_color(vec2 uv) {
	if (climate_mode == 5) {
		return texture(biome_field, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
	}
	if (climate_mode == 4) {
		return texture(drainage_field, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
	}
	vec4 data = texture(climate_field, clamp(uv, vec2(0.0), vec2(1.0)));
	if (climate_mode == 1) {
		float t = data.r * 140.0 - 80.0;
		vec3 cold = mix(vec3(0.08, 0.16, 0.58), vec3(0.86, 0.94, 1.0), clamp((t + 80.0) / 80.0, 0.0, 1.0));
		vec3 warm = mix(vec3(0.86, 0.94, 1.0), vec3(0.94, 0.16, 0.06), clamp(t / 60.0, 0.0, 1.0));
		return t < 0.0 ? cold : warm;
	}
	if (climate_mode == 2) {
		float rain = data.g;
		return rain < 0.25 ? mix(vec3(0.72, 0.52, 0.28), vec3(0.11, 0.69, 0.60), rain * 4.0) : mix(vec3(0.11, 0.69, 0.60), vec3(0.05, 0.14, 0.43), (rain - 0.25) / 0.75);
	}
	vec2 wind = normalize(data.ba * 2.0 - 1.0);
	vec2 tile = fract(uv * vec2(20.0 * map_size.x / map_size.y, 20.0)) - vec2(0.5);
	vec2 axis = vec2(dot(tile, wind), dot(tile, vec2(-wind.y, wind.x)));
	float shaft = (1.0 - smoothstep(0.018, 0.038, abs(axis.y))) * step(-0.25, axis.x) * step(axis.x, 0.23);
	float head = (1.0 - smoothstep(0.025, 0.045, abs(abs(axis.y) - (0.28 - axis.x)))) * step(0.08, axis.x) * step(axis.x, 0.28);
	return mix(vec3(0.12, 0.26, 0.34), vec3(0.94, 0.87, 0.62), max(shaft, head));
}
