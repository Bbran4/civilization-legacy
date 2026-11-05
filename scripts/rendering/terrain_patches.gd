extends RefCounted
## Camera-dependent geometry only. Source fields and authoring IDs are immutable.
const Field = preload("res://scripts/rendering/display_height_field.gd")
const BASE_CELLS = 8
const MAX_CELLS = 128
const MAX_PATCHES = 16
const LEVELS = 5
const PIXELS_PER_CELL = 4.0
var root: Node3D
var material: ShaderMaterial
var heights := PackedFloat32Array()
var source_size := Vector2i.ZERO
var extent := Vector2.ONE
var sea_height := 0.0
var texture: Texture2D
var count := Vector2i.ONE
var max_level := 0
var levels := PackedByteArray()
var lod_texture: ImageTexture
var radii := PackedFloat32Array([0,0,0,0,0])
var bands := PackedFloat32Array([1,1,1,1,1])
var weights := PackedFloat32Array([1,1,1,1,1])
var focus := Vector2.ZERO
var view_size := 0.0
var viewport_height := 800.0
var view_aspect := 1.6
var view_vertical := 0.82
var enabled := false
var mesh_changes := 0
var view_updates := 0
var _nodes: Array[MeshInstance3D] = []
var _meshes: Array[ArrayMesh] = []
func _init(parent: Node3D,shared_material: ShaderMaterial) -> void:
	material = shared_material
	root = Node3D.new()
	root.name = "TerrainPatches"
	parent.add_child(root)
	root.visible = false
func configure(values: PackedFloat32Array,size: Vector2i,world_extent: Vector2,sea: float,field_texture: Texture2D,bounds: Vector2) -> void:
	var resized := extent != world_extent
	heights = values
	source_size = size
	extent = world_extent
	sea_height = sea
	texture = field_texture
	enabled = maxi(size.x,size.y) > 513
	if not enabled:
		root.visible = false
		return
	var next_count := Vector2i((world_extent/maxf(world_extent.x,world_extent.y)*MAX_PATCHES).round()).max(Vector2i.ONE)
	var native_cells := maxi(size.x-1,size.y-1)/float(MAX_PATCHES)
	var cells := clampi(nearest_po2(roundi(native_cells)),BASE_CELLS,MAX_CELLS)
	var next_level := roundi(log(float(cells)/BASE_CELLS)/log(2.0))
	if next_count != count or next_level != max_level or _nodes.is_empty() or resized:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()
		_nodes.clear()
		_meshes.clear()
		count = next_count
		max_level = next_level
		for level in range(max_level+1):
			var mesh := PlaneMesh.new()
			mesh.size = extent/Vector2(count)
			mesh.subdivide_width = (BASE_CELLS << level)-1
			mesh.subdivide_depth = (BASE_CELLS << level)-1
			var arrays := mesh.surface_get_arrays(0)
			# Shared mesh metadata avoids the limited per-instance uniform buffer on GL.
			var colors := PackedColorArray()
			colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
			colors.fill(Color(1,1,1,float(level)/4.0))
			arrays[Mesh.ARRAY_COLOR] = colors
			var shared := ArrayMesh.new()
			shared.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			_meshes.append(shared)
		levels.resize(count.x*count.y)
		levels.fill(255)
		for y in range(count.y):
			for x in range(count.x):
				var node := MeshInstance3D.new()
				node.name = "Patch_%d_%d" % [x,y]
				node.material_override = material
				node.cast_shadow = root.get_parent().cast_shadow
				root.add_child(node)
				node.position = Vector3(((x+0.5)/count.x-0.5)*extent.x,0,((y+0.5)/count.y-0.5)*extent.y)
				_nodes.append(node)
		lod_texture = null
	var patch := extent/Vector2(count)
	for y in range(count.y):
		for x in range(count.x):
			_nodes[y*count.x+x].custom_aabb = AABB(Vector3(-patch.x*0.5,minf(0,bounds.x)-1,-patch.y*0.5),Vector3(patch.x,bounds.y-minf(0,bounds.x)+2,patch.y))
	if view_size <= 0: view_size = maxf(extent.x,extent.y)/8.0
	update_view(focus,view_size,viewport_height,view_aspect,view_vertical)
func update_view(center: Vector2,height: float,pixels: float,aspect: float,vertical: float) -> bool:
	focus = center
	view_size = maxf(0.001,height)
	viewport_height = maxf(1,pixels)
	view_aspect = aspect
	view_vertical = vertical
	if not enabled: return false
	view_updates += 1
	var patch := extent/Vector2(count)
	var diagonal := patch.length()
	var demand := maxf(patch.x,patch.y)*viewport_height/(view_size*PIXELS_PER_CELL)
	var cap := clampi(ceili(log(maxf(1,demand/BASE_CELLS))/log(2.0)-0.000001),0,max_level)
	var reach := view_size*maxf(1,aspect)*0.75/maxf(0.3,vertical)
	# The two-diagonal radius gap keeps the parent fully unmorphed wherever a
	# child patch exists. Fine boundary vertices therefore lie on its coarse edge.
	for level in range(LEVELS):
		radii[level] = reach+(max_level-level)*diagonal*2.0
		bands[level] = maxf(0.001,minf(reach*0.3,diagonal*0.5))
		weights[level] = smoothstep(float(BASE_CELLS << maxi(0,level-1)),float(BASE_CELLS << level),demand) if level > 0 else 1.0
	var changed := false
	for y in range(count.y):
		for x in range(count.x):
			var low := Vector2(x,y)*patch-extent*0.5
			var nearest := focus.clamp(low,low+patch)
			var distance := focus.distance_to(nearest)
			var selected := 0
			for level in range(1,cap+1):
				if distance < radii[level]: selected = level
			var index := y*count.x+x
			if levels[index] == selected: continue
			levels[index] = selected
			_nodes[index].mesh = _meshes[selected]
			mesh_changes += 1
			changed = true
	if changed or lod_texture == null:
		var image := Image.create_from_data(count.x,count.y,false,Image.FORMAT_R8,levels)
		if lod_texture == null: lod_texture = ImageTexture.create_from_image(image)
		else: lod_texture.update(image)
	return changed
func bind(target: ShaderMaterial,active: bool) -> void:
	target.set_shader_parameter("chunked_relief",active and enabled)
	if not enabled: return
	target.set_shader_parameter("relief_display_heights",texture)
	target.set_shader_parameter("relief_sea_height",sea_height)
	target.set_shader_parameter("relief_patch_count",count)
	target.set_shader_parameter("relief_patch_lods",lod_texture)
	target.set_shader_parameter("relief_focus",focus)
	target.set_shader_parameter("relief_extent",extent)
	target.set_shader_parameter("relief_radii",radii)
	target.set_shader_parameter("relief_bands",bands)
	target.set_shader_parameter("relief_weights",weights)
func full_grid_size() -> Vector2i:
	return count*(BASE_CELLS << max_level)+Vector2i.ONE
func level_at(uv: Vector2) -> int:
	var cell := Vector2i((uv*Vector2(count)).floor()).clamp(Vector2i.ZERO,count-Vector2i.ONE)
	return levels[cell.y*count.x+cell.x]
func raw_height(uv: Vector2) -> float:
	return maxf(sea_height,Field.sample(heights,source_size,uv))
func raw_triangle(uv: Vector2,cells: Vector2i) -> float:
	var p := uv.clamp(Vector2.ZERO,Vector2.ONE)*Vector2(cells)
	var cell := Vector2i(p.floor()).min(cells-Vector2i.ONE)
	var f := p-Vector2(cell)
	var a := raw_height(Vector2(cell)/Vector2(cells))
	var b := raw_height(Vector2(cell+Vector2i.RIGHT)/Vector2(cells))
	var c := raw_height(Vector2(cell+Vector2i.DOWN)/Vector2(cells))
	if f.x+f.y <= 1: return a+(b-a)*f.x+(c-a)*f.y
	var d := raw_height(Vector2(cell+Vector2i.ONE)/Vector2(cells))
	return d+(c-d)*(1-f.x)+(b-d)*(1-f.y)
func vertex_height(uv: Vector2,level: int) -> float:
	var fine := raw_height(uv)
	if level <= 0: return fine
	var coarse := raw_triangle(uv,count*(BASE_CELLS << (level-1)))
	var distance := ((uv-Vector2.ONE*0.5)*extent).distance_to(focus)
	var morph := smoothstep(0,bands[level],radii[level]-distance)*weights[level]
	return lerpf(coarse,fine,morph)
func sample(uv: Vector2) -> float:
	return sample_level(uv,level_at(uv))
func sample_level(uv: Vector2,level: int) -> float:
	var cells := count*(BASE_CELLS << level)
	var p := uv.clamp(Vector2.ZERO,Vector2.ONE)*Vector2(cells)
	var cell := Vector2i(p.floor()).min(cells-Vector2i.ONE)
	var f := p-Vector2(cell)
	var a := vertex_height(Vector2(cell)/Vector2(cells),level)
	var b := vertex_height(Vector2(cell+Vector2i.RIGHT)/Vector2(cells),level)
	var c := vertex_height(Vector2(cell+Vector2i.DOWN)/Vector2(cells),level)
	if f.x+f.y <= 1: return a+(b-a)*f.x+(c-a)*f.y
	var d := vertex_height(Vector2(cell+Vector2i.ONE)/Vector2(cells),level)
	return d+(c-d)*(1-f.x)+(b-d)*(1-f.y)

func triangle_count() -> int:
	if not enabled: return 0
	var total := 0
	for level in levels:
		var cells := BASE_CELLS << level
		total += cells*cells*2
	return total
