// Canonical geographic footprint shared by fills and border ribbons.
// Source heights define coastlines; carved relief must not redefine land ownership.
uniform sampler2D geography_heights : filter_linear, repeat_disable;
uniform sampler2D geography_water : filter_linear, repeat_disable;
uniform bool geography_has_water = false;
float geographic_field(vec2 at) {
    float coast = texture(geography_heights, at).r - 0.2;
    float lake = geography_has_water ? texture(geography_water, at).g : 0.0;
    return min(coast, (0.5 - lake) * 0.1);
}
bool geographic_land(vec2 at) { return geographic_field(at) >= 0.0; }
