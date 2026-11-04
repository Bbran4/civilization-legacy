// Shared by ground and foliage. Political overlays do not pass through this tint.
uniform vec3 map_sun_direction = vec3(-0.353,0.788,0.504);
uniform vec3 map_sun_color = vec3(1.0,0.95,0.86);
uniform vec3 map_sky_color = vec3(0.76,0.84,0.95);
uniform float map_sun_strength = 0.4;
uniform float map_sky_strength = 0.67;
uniform vec3 map_haze_focus = vec3(0.0);
uniform vec3 map_haze_forward = vec3(0.0,0.0,-1.0);
uniform float map_haze_span = 100.0;
uniform float map_haze_strength = 0.0;
vec3 map_light(vec3 normal) {
    float key = max(dot(normalize(normal),normalize(map_sun_direction)),0.0);
    float sky = mix(0.82,1.0,clamp(normal.y*0.5+0.5,0.0,1.0));
    return map_sky_color*map_sky_strength*sky+map_sun_color*map_sun_strength*key;
}
vec3 map_haze(vec3 color, vec3 position, float relief) {
    float distance = dot(position-map_haze_focus,map_haze_forward);
    float amount = smoothstep(-0.05,0.65,distance/map_haze_span)*map_haze_strength*relief;
    return mix(color,vec3(0.48,0.60,0.68),amount);
}
