// Shared numeric height sampling, matching HeightmapGrid mesh triangles.
uniform sampler2D height_coarse : filter_nearest, repeat_disable;
uniform sampler2D height_fine : filter_nearest, repeat_disable;
uniform float field_blend = 1.0;

float triangle_height(sampler2D field, vec2 uv) {
	ivec2 size = textureSize(field, 0);
	vec2 p = clamp(uv, vec2(0.0), vec2(1.0)) * vec2(size - ivec2(1));
	ivec2 cell = min(ivec2(floor(p)), size - ivec2(2));
	vec2 f = p - vec2(cell);
	float a = texelFetch(field, cell, 0).r;
	float b = texelFetch(field, cell + ivec2(1, 0), 0).r;
	float c = texelFetch(field, cell + ivec2(0, 1), 0).r;
	float d = texelFetch(field, cell + ivec2(1, 1), 0).r;
	return f.x + f.y <= 1.0 ? a + (b - a) * f.x + (c - a) * f.y : d + (c - d) * (1.0 - f.x) + (b - d) * (1.0 - f.y);
}

float displayed_height(vec2 position) {
	vec2 uv = position / map_size + vec2(0.5);
	return mix(triangle_height(height_coarse, uv), triangle_height(height_fine, uv), field_blend);
}
