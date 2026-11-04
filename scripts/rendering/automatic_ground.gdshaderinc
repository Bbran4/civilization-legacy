// Procedural material tiles are derived from saved choices; placement reads
// stable source geography and active relief beneath paint and political overlays.
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
uniform sampler2D ground_regions : filter_linear, repeat_disable;
uniform float region_lapse = 0.65;
uniform float region_snow_cooling = 0.14;
vec2 ground_bank(vec2 at) {
    if (!geography_has_water) return vec2(0.0);
    // Soft local estimate, not a second coastline or hydrology classification.
    // Include diagonals so banks do not depend on the direction of a river.
    vec2 reach = max(vec2(1.2)/map_extent,vec2(1.5)/vec2(textureSize(geography_water,0)));
    vec2 wet = texture(geography_water,at).rg*4.0;
    wet += texture(geography_water,at+vec2(reach.x,0.0)).rg;
    wet += texture(geography_water,at-vec2(reach.x,0.0)).rg;
    wet += texture(geography_water,at+vec2(0.0,reach.y)).rg;
    wet += texture(geography_water,at-vec2(0.0,reach.y)).rg;
    wet += texture(geography_water,at+reach*0.65).rg;
    wet += texture(geography_water,at-reach*0.65).rg;
    wet += texture(geography_water,at+reach*vec2(0.65,-0.65)).rg;
    wet += texture(geography_water,at+reach*vec2(-0.65,0.65)).rg;
    return clamp(wet/6.0,vec2(0.0),vec2(1.0));
}
vec3 automatic_ground(vec2 at, float height, float light) {
    vec2 world = at*map_extent;
    vec2 step_uv = max(texel_size*2.0,vec2(0.5)/map_extent);
    float dx = (texture(height_field,at+vec2(step_uv.x,0.0)).r-texture(height_field,at-vec2(step_uv.x,0.0)).r)*ground_height_scale/(2.0*step_uv.x*map_extent.x);
    float dz = (texture(height_field,at+vec2(0.0,step_uv.y)).r-texture(height_field,at-vec2(0.0,step_uv.y)).r)*ground_height_scale/(2.0*step_uv.y*map_extent.y);
    float slope = length(vec2(dx,dz));
    vec3 normal = normalize(vec3(-dx,1.0,-dz));
    float variation = texture(ground_grass,world/90.0).a;
    float breakup = texture(ground_earth,world/17.0).a-0.5;
    vec2 region = texture(ground_regions,at).rg;
    float warmth = clamp(region.r-max(0.0,texture(geography_heights,at).r-0.2)*region_lapse,0.0,1.0);
    float dryness = (1.0-smoothstep(0.25,0.6,region.g))*smoothstep(0.3,0.7,warmth);
    vec2 bank = ground_bank(at);
    float moisture = max(bank.r,bank.g);
    vec2 tile = world/ground_scale;
    // Two differently oriented samples break the obvious small-tile repetition.
    vec2 turned_tile = vec2(tile.x*0.8-tile.y*0.6,tile.x*0.6+tile.y*0.8)*0.73+vec2(0.37,0.61);
    vec4 grass_tile = mix(texture(ground_grass,tile),texture(ground_grass,turned_tile),0.35+variation*0.3);
    vec4 earth_tile = mix(texture(ground_earth,tile),texture(ground_earth,turned_tile),0.35+variation*0.3);
    vec4 sand_tile = texture(ground_sand,tile);
    vec4 snow_tile = texture(ground_snow,tile);
    float grass = smoothstep(0.15,0.85,ground_grass_cover+(variation-0.5)*0.65+breakup*0.15+moisture*0.18+(grass_tile.a-earth_tile.a)*0.18);
    grass *= smoothstep(0.0,0.1,ground_grass_cover);
    grass *= mix(0.4,1.0,smoothstep(0.12,0.55,region.g+moisture*0.4));
    // River edges expose damp soil; the outer bank retains a greener fringe.
    grass *= 1.0-smoothstep(0.12,0.7,bank.r)*0.75;
    vec2 shore_step = min(step_uv,vec2(0.4)/map_extent);
    float shore_x = (geographic_field(at+vec2(shore_step.x,0.0))-geographic_field(at-vec2(shore_step.x,0.0)))/(2.0*shore_step.x*map_extent.x);
    float shore_z = (geographic_field(at+vec2(0.0,shore_step.y))-geographic_field(at-vec2(0.0,shore_step.y)))/(2.0*shore_step.y*map_extent.y);
    float shore_distance = geographic_field(at)/max(length(vec2(shore_x,shore_z)),0.00001);
    float beach_width = 1.2+(variation-0.5)*0.65+breakup*0.4;
    float beach = 1.0-smoothstep(0.08,beach_width,shore_distance+(sand_tile.a-0.5)*0.2);
    beach = max(beach,smoothstep(0.03,0.5,bank.g)*0.8);
    beach *= 1.0-smoothstep(0.25,0.8,slope);
    float exposure = smoothstep(ground_rock_slope*0.65,ground_rock_slope*1.3,slope*(1.0+breakup*0.3));
    exposure = max(exposure,smoothstep(0.68,0.9,height+breakup*0.025)*0.45);
    // Stable world-height mapping avoids texture movement during zoom morphing.
    vec3 position = vec3(world.x,(height-0.2)*ground_height_scale,world.y)/ground_scale;
    vec3 weights = pow(abs(normal),vec3(4.0));
    weights /= max(dot(weights,vec3(1.0)),0.0001);
    vec3 rock = texture(ground_rock,position.zy).rgb*weights.x+texture(ground_rock,position.xz).rgb*weights.y+texture(ground_rock,position.xy).rgb*weights.z;
    float local_snow_line = ground_snow_line-(1.0-warmth)*region_snow_cooling;
    float snow = smoothstep(local_snow_line-0.04,local_snow_line+0.055,height+(variation-0.5)*0.04+breakup*0.025+(snow_tile.a-0.5)*0.025);
    snow *= 1.0-smoothstep(1.0,2.5,slope)*0.65;
    if (ground_snow_line >= 0.999) snow = 0.0;
    // Layered weights sum to one, keeping transitions from brightening or darkening
    // just because several materials meet. Dampness changes albedo, never height.
    vec3 earth = earth_tile.rgb*mix(vec3(1.0),vec3(0.66,0.71,0.65),moisture);
    earth = mix(earth,mix(earth,sand_tile.rgb,0.35),dryness);
    vec3 grass_color = grass_tile.rgb*mix(vec3(0.83,0.94,0.90),vec3(1.0),warmth);
    grass_color = mix(grass_color,grass_color*vec3(1.14,1.03,0.76),dryness*0.65);
    vec3 color = mix(earth,grass_color,grass);
    color = mix(color,sand_tile.rgb*mix(1.0,0.78,moisture),beach);
    color = mix(color,rock,exposure);
    // Wet ground stays darker even where the regional field promotes grass.
    color *= mix(1.0,0.72,moisture);
    color = mix(color,snow_tile.rgb,snow);
    return color*(0.45+light*0.65);
}
