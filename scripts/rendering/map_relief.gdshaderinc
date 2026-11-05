// Shared displayed-surface sampling. CPU picking uses the same triangles and morphs.
// Small sources and the comparison fallback retain the bounded grid.
uniform sampler2D relief_vertices : filter_nearest, repeat_disable;
uniform float relief_amount = 0.0;
float legacy_relief_height(vec2 at) {
    ivec2 size = textureSize(relief_vertices,0);
    vec2 p = clamp(at,vec2(0.0),vec2(1.0))*vec2(size-1);
    ivec2 cell = min(ivec2(p),size-2);
    vec2 f = p-vec2(cell);
    float a = texelFetch(relief_vertices,cell,0).r;
    float b = texelFetch(relief_vertices,cell+ivec2(1,0),0).r;
    float c = texelFetch(relief_vertices,cell+ivec2(0,1),0).r;
    float d = texelFetch(relief_vertices,cell+ivec2(1,1),0).r;
    return (f.x+f.y<=1.0 ? a+(b-a)*f.x+(c-a)*f.y : d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y))*relief_amount;
}

// Patch geometry and all draped consumers sample the same morphed triangles.
uniform bool chunked_relief = false;
uniform sampler2D relief_display_heights : filter_linear, repeat_disable;
uniform sampler2D relief_patch_lods : filter_nearest, repeat_disable;
uniform ivec2 relief_patch_count = ivec2(1);
uniform vec2 relief_extent = vec2(192.0);
uniform vec2 relief_focus = vec2(0.0);
uniform float relief_sea_height = 0.0;
uniform float relief_radii[5];
uniform float relief_bands[5];
uniform float relief_weights[5];
float patch_raw_height(vec2 at) {
    return max(relief_sea_height,texture(relief_display_heights,at).r);
}
float patch_raw_triangle(vec2 at,vec2 cells) {
    vec2 p=clamp(at,vec2(0.0),vec2(1.0))*cells;
    vec2 cell=min(floor(p),cells-1.0);
    vec2 f=p-cell;
    float a=patch_raw_height(cell/cells);
    float b=patch_raw_height((cell+vec2(1.0,0.0))/cells);
    float c=patch_raw_height((cell+vec2(0.0,1.0))/cells);
    if(f.x+f.y<=1.0) return a+(b-a)*f.x+(c-a)*f.y;
    float d=patch_raw_height((cell+vec2(1.0))/cells);
    return d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
}
float patch_vertex_height(vec2 at,int level) {
    float fine=patch_raw_height(at);
    if(level<=0) return fine;
    float coarse=patch_raw_triangle(at,vec2(relief_patch_count)*8.0*exp2(float(level-1)));
    float distance=length((at-0.5)*relief_extent-relief_focus);
    float morph=smoothstep(0.0,relief_bands[level],relief_radii[level]-distance)*relief_weights[level];
    return mix(coarse,fine,morph);
}
float relief_height(vec2 at) {
    if(!chunked_relief) return legacy_relief_height(at);
    ivec2 patch=clamp(ivec2(floor(at*vec2(relief_patch_count))),ivec2(0),relief_patch_count-1);
    int level=int(round(texelFetch(relief_patch_lods,patch,0).r*255.0));
    vec2 cells=vec2(relief_patch_count)*8.0*exp2(float(level));
    vec2 p=clamp(at,vec2(0.0),vec2(1.0))*cells;
    vec2 cell=min(floor(p),cells-1.0);
    vec2 f=p-cell;
    float a=patch_vertex_height(cell/cells,level);
    float b=patch_vertex_height((cell+vec2(1.0,0.0))/cells,level);
    float c=patch_vertex_height((cell+vec2(0.0,1.0))/cells,level);
    if(f.x+f.y<=1.0) return (a+(b-a)*f.x+(c-a)*f.y)*relief_amount;
    float d=patch_vertex_height((cell+vec2(1.0))/cells,level);
    return (d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y))*relief_amount;
}
