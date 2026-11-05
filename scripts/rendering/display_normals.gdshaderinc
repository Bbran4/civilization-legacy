// Full-resolution display heights are already in local world units.
uniform sampler2D display_heights : filter_linear, repeat_disable;
uniform float display_sea_height = 0.0;
uniform vec2 display_texel_size = vec2(0.001);
vec3 display_normal(vec2 at, vec2 extent, vec2 footprint) {
    // Filter distant derivatives over their screen footprint to avoid shimmer.
    vec2 reach = max(display_texel_size,footprint);
    vec2 lo = max(at-reach,display_texel_size*0.5);
    vec2 hi = min(at+reach,vec2(1.0)-display_texel_size*0.5);
    float dx = max(display_sea_height,texture(display_heights,vec2(hi.x,at.y)).r)-max(display_sea_height,texture(display_heights,vec2(lo.x,at.y)).r);
    float dz = max(display_sea_height,texture(display_heights,vec2(at.x,hi.y)).r)-max(display_sea_height,texture(display_heights,vec2(at.x,lo.y)).r);
    vec2 span = max((hi-lo)*extent,vec2(0.000001));
    return normalize(vec3(-dx/span.x,1.0,-dz/span.y));
}
