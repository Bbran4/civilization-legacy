shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://scripts/rendering/map_geography.gdshaderinc"
uniform float coast_width = 4.5;
uniform float coast_distant_scale = 0.35;
uniform sampler2D height_field : filter_linear, repeat_disable;
uniform vec2 texel_size = vec2(0.001);
uniform bool shaded_relief = true;
uniform bool paint_enabled = false;
uniform sampler2D paint_field : source_color, filter_linear, repeat_disable;
uniform bool height_enabled = true;
uniform bool water_enabled = false;
uniform sampler2D water_field : filter_linear, repeat_disable;
uniform bool provinces_enabled = false;
uniform bool province_fill = true;
uniform bool vector_borders = false;
uniform int selected_province = 0;
uniform int merge_ids[32];
uniform int merge_count = 0;
uniform sampler2D province_field : filter_nearest, repeat_disable;
uniform sampler2D nation_colors : source_color, filter_nearest, repeat_disable;
uniform bool smooth_borders = true;
uniform sampler2D province_kinds : filter_nearest, repeat_disable;
float sample_id(vec2 at) {
    vec2 c = round(texture(province_field, at).rg * 255.0);
    return c.r + c.g * 256.0;
}
// Same four-triangle reconstruction as ProvinceBorderPaths._contours.
float categorical_id(vec2 uv) {
    if (!smooth_borders) return sample_id(uv);
    vec2 dimensions = vec2(textureSize(province_field,0));
    vec2 p = clamp(uv*dimensions-0.5,vec2(0.0),dimensions-1.00001);
    vec2 t = fract(p);
    vec2 cell = floor(p);
    float ids[4];
    ids[0]=sample_id((cell+vec2(0.5,0.5))/dimensions);
    ids[1]=sample_id((cell+vec2(1.5,0.5))/dimensions);
    ids[2]=sample_id((cell+vec2(1.5,1.5))/dimensions);
    ids[3]=sample_id((cell+vec2(0.5,1.5))/dimensions);
    if (ids[0]==ids[1] && ids[0]==ids[2] && ids[0]==ids[3]) return ids[0];
    float middle=ids[0]; int best=0;
    for (int i=0;i<4;i++) {
        int count=0;
        for (int j=0;j<4;j++) if (ids[i]==ids[j]) count++;
        if (count>best || (count==best && ids[i]<middle)) { middle=ids[i]; best=count; }
    }
    int a=0; int b=1; vec3 w;
    if (t.y<=t.x && t.y<=1.0-t.x) { w=vec3(1.0-t.x-t.y,t.x-t.y,2.0*t.y); }
    else if (t.x>=t.y && t.x>=1.0-t.y) { a=1; b=2; w=vec3(t.x-t.y,t.x+t.y-1.0,2.0*(1.0-t.x)); }
    else if (t.y>=t.x && t.y>=1.0-t.x) { a=2; b=3; w=vec3(t.x+t.y-1.0,t.y-t.x,2.0*(1.0-t.y)); }
    else { a=3; b=0; w=vec3(t.y-t.x,1.0-t.x-t.y,2.0*t.x); }
    bool two_pairs=(ids[0]==ids[1] && ids[2]==ids[3] && ids[0]!=ids[2]) || (ids[0]==ids[2] && ids[1]==ids[3] && ids[0]!=ids[1]) || (ids[0]==ids[3] && ids[1]==ids[2] && ids[0]!=ids[1]);
    float chosen=ids[0]; float largest=-1.0;
    for (int i=0;i<4;i++) {
        float weight=0.0;
        if (ids[i]==ids[a]) weight+=w.x;
        if (ids[i]==ids[b]) weight+=w.y;
        if (two_pairs) weight+=0.5*w.z;
        else if (ids[i]==middle) weight+=w.z;
        if (weight>largest || (weight==largest && ids[i]<chosen)) { largest=weight; chosen=ids[i]; }
    }
    return chosen;
}
// Province IDs own political boundaries, not the continuous geographic edge.
// At a coastline extend only the matching class's local ownership to that edge.
float province_id(vec2 uv) {
    float id = categorical_id(uv);
    bool land = geographic_land(uv);
    bool id_land = id > 0.5 && texelFetch(province_kinds,ivec2(int(id)%256,int(id)/256),0).r < 0.5;
    int zone = int(round(texture(province_field,uv).b*255.0));
    if ((id > 0.5 && id_land == land) || (id < 0.5 && (!land || zone == 3))) return id;
    vec2 dimensions = vec2(textureSize(province_field,0));
    vec2 p = clamp(uv*dimensions-0.5,vec2(0.0),dimensions-1.00001);
    vec2 t = fract(p);
    vec2 cell = floor(p);
    float chosen = 0.0;
    float largest = -1.0;
    for (int y=0;y<2;y++) for (int x=0;x<2;x++) {
        vec2 at = (cell+vec2(float(x),float(y))+0.5)/dimensions;
        float candidate = sample_id(at);
        int candidate_zone = int(round(texture(province_field,at).b*255.0));
        bool candidate_land = candidate > 0.5 && texelFetch(province_kinds,ivec2(int(candidate)%256,int(candidate)/256),0).r < 0.5;
        bool eligible = candidate > 0.5 ? candidate_land == land : (!land && candidate_zone != 3);
        float weight = (x==0 ? 1.0-t.x : t.x)*(y==0 ? 1.0-t.y : t.y);
        if (eligible && (weight>largest || (weight==largest && candidate<chosen))) { chosen=candidate; largest=weight; }
    }
    return chosen;
}
float geographic_outline(vec2 at) {
    float field = geographic_field(at);
    float gradient = length(vec2(dFdx(field),dFdy(field)));
    if (gradient < 0.0000001) return 0.0;
    vec2 dimensions = vec2(textureSize(geography_heights,0));
    float pixels_per_sample = 1.0/max(length(dFdx(at)*dimensions),length(dFdy(at)*dimensions));
    float width = coast_width*mix(coast_distant_scale,1.0,smoothstep(0.5,3.0,pixels_per_sample));
    if (width <= 0.0) return 0.0;
    return 1.0-smoothstep(max(0.0,width*0.5-0.5),width*0.5+0.5,abs(field)/gradient);
}
vec3 province_tint(float id) {
    return 0.3 + 0.6 * fract(sin(vec3(id,id+17.0,id+43.0))*43758.5453);
}
void fragment() {
	float h = texture(height_field, UV).r;
	float value = h;
	if (shaded_relief) {
		float dx = texture(height_field, UV + vec2(texel_size.x, 0.0)).r - texture(height_field, UV - vec2(texel_size.x, 0.0)).r;
		float dy = texture(height_field, UV + vec2(0.0, texel_size.y)).r - texture(height_field, UV - vec2(0.0, texel_size.y)).r;
		float resolution_scale = float(max(textureSize(height_field, 0).x, textureSize(height_field, 0).y)) / 1025.0;
		vec3 n = normalize(vec3(-dx * 45.0 * resolution_scale, 1.0, -dy * 45.0 * resolution_scale));
		float light = 0.55 + 0.45 * max(dot(n, normalize(vec3(-0.6, 0.8, -0.4))), 0.0);
		value = h < 0.2 ? h * 0.35 : clamp(0.25 + h * 0.7, 0.0, 1.0) * light;
	}
	vec3 color = height_enabled ? vec3(value) : vec3(0.02);
	// Appearance is above the height/surface shading and below every overlay.
	if (paint_enabled && shaded_relief && geographic_land(UV)) {
		vec4 paint = texture(paint_field,UV);
		color = mix(color,paint.rgb*(0.55+value*0.65),paint.a);
	}
	if (provinces_enabled && shaded_relief) {
		float id = province_id(UV);
		int zone = int(round(texture(province_field, UV).b * 255.0));
		// Keep unassigned terrain visually distinct from generated regions:
		// coastal sea band, impassable land, and ordinary/unassigned water.
		if (id < 0.5 && zone == 2) color = vec3(0.10, 0.30, 0.46);
		if (id < 0.5 && zone == 3) color = vec3(0.24, 0.24, 0.27);
		if (id < 0.5 && zone == 0 && !geographic_land(UV)) color = vec3(0.055, 0.16, 0.24);
		if (id > 0.5) {
			bool ocean = texelFetch(province_kinds,ivec2(int(id)%256,int(id)/256),0).r > 0.5;
			vec4 nation = texelFetch(nation_colors,ivec2(int(id)%256,int(id)/256),0);
			vec3 tint = nation.a > 0.5 ? nation.rgb : province_tint(id);
			color = ocean ? vec3(0.27, 0.42, 0.61) : (province_fill ? mix(color, tint * (0.65 + value * 0.35), nation.a > 0.5 ? 0.82 : 0.62) : color);
			if (!vector_borders) {
			vec2 border_step = max(texel_size, fwidth(UV) * 1.25);
			bool edge = province_id(UV + vec2(border_step.x, 0.0)) != id || province_id(UV + vec2(0.0, border_step.y)) != id;
			if (ocean) edge = edge || province_id(UV - vec2(border_step.x, 0.0)) != id || province_id(UV - vec2(0.0, border_step.y)) != id;
			if (edge) color = ocean ? vec3(0.055, 0.08, 0.12) : color * 0.35;
			}
			bool selected = int(id) == selected_province;
			for (int i = 0; i < 32; i++) {
				if (i >= merge_count) break;
				selected = selected || int(id) == merge_ids[i];
			}
			if (selected) color = mix(color, vec3(1.0, 0.8, 0.3), 0.45);
		}
	}
	if (water_enabled && (shaded_relief || !height_enabled)) {
		vec2 water = texture(water_field, UV).rg;
		color = mix(color, vec3(0.223529, 0.498039, 0.658824), water.r);
		color = mix(color, vec3(0.156863, 0.403922, 0.537255), water.g);
	}
	if (provinces_enabled && shaded_relief && vector_borders) color = mix(color,vec3(0.055,0.065,0.07),geographic_outline(UV));
	ALBEDO = color;
}
