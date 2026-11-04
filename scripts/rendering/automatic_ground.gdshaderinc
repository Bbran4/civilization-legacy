// Procedural material tiles are derived from saved choices; material placement
// reads the active terrain and canonical geography, beneath paint and overlays.
uniform bool textures_enabled = false;
uniform sampler2D ground_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_earth : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float ground_scale = 6.0;
uniform float ground_grass_cover = 0.72;
uniform float ground_rock_slope = 0.7;
uniform float ground_snow_line = 0.82;
uniform float ground_height_scale = 12.0;
float ground_wetness(vec2 at) {
    vec2 wet = texture(geography_water,at).rg;
    return max(wet.r,wet.g);
}
vec3 automatic_ground(vec2 at, float height, float light) {
    vec2 world = at*map_extent;
    vec2 step_uv = max(texel_size*2.0,vec2(0.5)/map_extent);
    float dx = (texture(height_field,at+vec2(step_uv.x,0.0)).r-texture(height_field,at-vec2(step_uv.x,0.0)).r)*ground_height_scale/(2.0*step_uv.x*map_extent.x);
    float dz = (texture(height_field,at+vec2(0.0,step_uv.y)).r-texture(height_field,at-vec2(0.0,step_uv.y)).r)*ground_height_scale/(2.0*step_uv.y*map_extent.y);
    float slope = length(vec2(dx,dz));
    vec3 normal = normalize(vec3(-dx,1.0,-dz));
    float variation = texture(ground_grass,world/90.0).a;
    float moisture = 0.0;
    if (geography_has_water) {
        vec2 reach = vec2(0.9)/map_extent;
        moisture = max(max(ground_wetness(at+vec2(reach.x,0.0)),ground_wetness(at-vec2(reach.x,0.0))),max(ground_wetness(at+vec2(0.0,reach.y)),ground_wetness(at-vec2(0.0,reach.y))));
    }
    vec2 tile = world/ground_scale;
    float grass = smoothstep(0.15,0.85,ground_grass_cover+(variation-0.5)*0.65+moisture*0.25)*smoothstep(0.0,0.1,ground_grass_cover);
    vec3 color = mix(texture(ground_earth,tile).rgb,texture(ground_grass,tile).rgb,grass);
    vec2 shore_step = min(step_uv,vec2(0.4)/map_extent);
    float shore_x = (geographic_field(at+vec2(shore_step.x,0.0))-geographic_field(at-vec2(shore_step.x,0.0)))/(2.0*shore_step.x*map_extent.x);
    float shore_z = (geographic_field(at+vec2(0.0,shore_step.y))-geographic_field(at-vec2(0.0,shore_step.y)))/(2.0*shore_step.y*map_extent.y);
    float shore_distance = geographic_field(at)/max(length(vec2(shore_x,shore_z)),0.00001);
    float beach = (1.0-smoothstep(0.2,1.2,shore_distance))*(1.0-smoothstep(0.3,0.8,slope));
    color = mix(color,texture(ground_sand,tile).rgb,beach);
    float exposure = smoothstep(ground_rock_slope*0.65,ground_rock_slope*1.3,slope);
    exposure = max(exposure,smoothstep(0.68,0.9,height)*0.45);
    // Stable world-height mapping avoids texture movement during zoom morphing.
    vec3 position = vec3(world.x,(height-0.2)*ground_height_scale,world.y)/ground_scale;
    vec3 weights = pow(abs(normal),vec3(4.0));
    weights /= max(dot(weights,vec3(1.0)),0.0001);
    vec3 rock = texture(ground_rock,position.zy).rgb*weights.x+texture(ground_rock,position.xz).rgb*weights.y+texture(ground_rock,position.xy).rgb*weights.z;
    color = mix(color,rock,exposure);
    float snow = smoothstep(ground_snow_line-0.025,ground_snow_line+0.045,height+(variation-0.5)*0.025);
    snow *= 1.0-smoothstep(1.0,2.5,slope)*0.65;
    if (ground_snow_line >= 0.999) snow = 0.0;
    color = mix(color,texture(ground_snow,tile).rgb,snow);
    return color*(0.45+light*0.65);
}
