// The renderer owns this bounded grid. CPU picking uses the same triangle diagonal.
uniform sampler2D relief_vertices : filter_nearest, repeat_disable;
uniform float relief_amount = 0.0;
float relief_height(vec2 at) {
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
