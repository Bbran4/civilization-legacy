shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float width_pixels = 1.3;
uniform int border_style = 0;
uniform float dash_length = 6.5;
uniform vec4 side_a : source_color = vec4(0.8,0.1,0.1,1.0);
uniform vec4 side_b : source_color = vec4(0.1,0.2,0.8,1.0);
void vertex() {
	vec2 normal = COLOR.rg * 2.0 - 1.0;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX,1.0);
	vec4 neighbor = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX + vec3(normal.x,0.0,normal.y),1.0);
	vec2 direction = (neighbor.xy/neighbor.w - clip.xy/clip.w) * VIEWPORT_SIZE;
	direction = normalize(direction + vec2(0.0000001));
	clip.xy += direction * (width_pixels * 0.5) * UV.y * (COLOR.b * 3.0) * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}
void fragment() {
	float aa = max(fwidth(UV.y),0.02);
	float edge = 1.0-smoothstep(1.0-aa,1.0,abs(UV.y));
	vec3 color = vec3(0.055,0.065,0.07);
	float alpha = edge;
	if (border_style == 0) {
		float phase = abs(fract(UV.x/dash_length)-0.5);
		float along_aa = max(fwidth(UV.x/dash_length),0.005);
		alpha *= 1.0-smoothstep(0.20-along_aa,0.20+along_aa,phase);
	}
	if (border_style == 2) {
		vec4 side = UV.y >= 0.0 ? side_a : side_b;
		float core = 1.0-smoothstep(0.28-aa,0.28+aa,abs(UV.y));
		float glow = side.a * (1.0-smoothstep(0.35,1.0,abs(UV.y))) * 0.9;
		color = mix(side.rgb,color,core);
		alpha *= max(core,glow);
	}
	ALBEDO = color;
	ALPHA = alpha;
}
