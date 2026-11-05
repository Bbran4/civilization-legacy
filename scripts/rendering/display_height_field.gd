extends RefCounted
## CPU-only job. Inputs are isolated packed-array snapshots; the producer cannot mutate them.
## No scene nodes, rendering resources or GPU operations are touched by the worker.
const MAX_RELIEF_CELLS = 512
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
var key := ""
var base := PackedFloat32Array()
var mask := PackedByteArray()
var levels := PackedFloat32Array()
var size := Vector2i.ZERO
var extent := Vector2.ONE
var offset := 0.0
var elevation := 1.0
var datum := 0.2
var sea_height := 0.0
var mesh_size := Vector2i.ZERO
var heights := PackedFloat32Array()
var mesh_heights := PackedFloat32Array()
var bounds := Vector2(INF,-INF)
var elapsed_usec := 0
func build() -> void:
	var started := Time.get_ticks_usec()
	heights.resize(base.size())
	var scale := maxf(extent.x,extent.y)/192.0
	sea_height = (offset+(0.2-datum)*elevation)*scale
	var wet := mask.size() == base.size()*4 and levels.size() == base.size()
	for i in range(base.size()):
		var h := base[i]
		if wet and (mask[i*4] > 0 or mask[i*4+1] > 0) and levels[i] >= 0:
			h = maxf(h,levels[i])
		heights[i] = (offset+(h-datum)*elevation)*scale
	mesh_size = Grid.sample_size_for(extent,mini(MAX_RELIEF_CELLS,maxi(size.x,size.y)-1))
	mesh_heights.resize(mesh_size.x*mesh_size.y)
	for y in range(mesh_size.y):
		for x in range(mesh_size.x):
			var h := maxf(sea_height,sample(heights,size,Vector2(x,y)/Vector2(mesh_size-Vector2i.ONE)))
			mesh_heights[y*mesh_size.x+x] = h
			bounds.x = minf(bounds.x,h)
			bounds.y = maxf(bounds.y,h)
	elapsed_usec = Time.get_ticks_usec()-started
	# Cached results need only the full display field and the bounded mesh field.
	base = PackedFloat32Array()
	mask = PackedByteArray()
	levels = PackedFloat32Array()
static func sample(values: PackedFloat32Array, dimensions: Vector2i, uv: Vector2) -> float:
	var p := (uv*Vector2(dimensions)-Vector2.ONE*0.5).clamp(Vector2.ZERO,Vector2(dimensions-Vector2i.ONE))
	var x := mini(int(p.x),dimensions.x-2)
	var y := mini(int(p.y),dimensions.y-2)
	var f := p-Vector2(x,y)
	return lerpf(lerpf(values[y*dimensions.x+x],values[y*dimensions.x+x+1],f.x),lerpf(values[(y+1)*dimensions.x+x],values[(y+1)*dimensions.x+x+1],f.x),f.y)
