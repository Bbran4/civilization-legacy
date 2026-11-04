extends Node3D
const Meshes = preload("res://scripts/rendering/forest_meshes.gd")
const Settings = preload("res://scripts/domain/forest_settings.gd")
const MAX_ATTEMPTS = 160000
const CHUNKS = 8
var material := ShaderMaterial.new()
var meshes: Array[ArrayMesh] = [Meshes.build(false),Meshes.build(true)]
var positions := PackedVector2Array()
var kinds := PackedByteArray()
var scales := PackedFloat32Array()
var key := ""
var layout_builds := 0
var attempts := 0
var _bounds := Vector2(INF,INF)
var cover_texture: ImageTexture
var detail := 0.0
func _init() -> void:
	material.shader = preload("res://scripts/rendering/forest.gdshader")
func refresh(terrain: Node) -> void:
	var settings: Dictionary = terrain.tree_settings
	var error := Settings.validate(settings)
	if not error.is_empty():
		push_error(error)
		visible = false
		terrain.map_renderer.set_forest_overview(null,0.0,false)
		return
	if not settings.enabled or not terrain.tree_layer_visible or not terrain.shaded_relief:
		visible = false
		terrain.map_renderer.set_forest_overview(null,0.0,false)
		return
	var water_key: String = terrain.water_layer.hydraulic_fingerprint() if terrain.water_layer_current() else ""
	var ceiling: float = settings.tree_line/100.0
	var slope: float = settings.max_slope
	if terrain.texture_settings.enabled:
		ceiling = minf(ceiling,terrain.texture_settings.snow_height/100.0-0.04)
		slope = minf(slope,terrain.texture_settings.rock_angle*0.75)
	var next_key: String = terrain.water_source_hash+"/"+water_key+"/"+terrain.map_seed+"/"+JSON.stringify(settings)+"/"+str(ceiling)+"/"+str(slope)
	if next_key != key:
		_build(terrain,ceiling,tan(deg_to_rad(slope)))
		key = next_key
	update_presentation(terrain)
func update_presentation(terrain: Node) -> void:
	visible = terrain.tree_settings.enabled and terrain.tree_layer_visible and terrain.shaded_relief
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var extent: Vector2 = terrain.display_size()
		var tree_size: float = minf(maxf(extent.x,extent.y)/192.0,minf(extent.x,extent.y)/20.0)*terrain.tree_settings.size
		var pixels: float = tree_size*get_viewport().get_visible_rect().size.y/maxf(0.001,camera.size)
		detail = smoothstep(4.0,12.0,pixels)
	else:
		detail = 1.0
	material.set_shader_parameter("tree_detail",detail)
	terrain.map_renderer.set_forest_overview(cover_texture,1.0-detail,visible)
	for child in get_children(): child.visible = detail > 0.0
	terrain.map_renderer.bind_relief_material(material)
	var bounds: Vector2 = terrain.map_renderer.mesh_bounds
	if bounds != _bounds:
		_bounds = bounds
		for child in get_children():
			var rect: Rect2 = child.get_meta("footprint")
			var height: float = child.get_meta("height")
			child.custom_aabb = AABB(Vector3(rect.position.x,minf(0,bounds.x)-1,rect.position.y),Vector3(rect.size.x,maxf(0,bounds.y)-minf(0,bounds.x)+height+2,rect.size.y))
func _build(terrain: Node, ceiling: float, max_slope: float) -> void:
	layout_builds += 1
	positions.clear()
	kinds.clear()
	scales.clear()
	attempts = 0
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var settings: Dictionary = terrain.tree_settings
	if settings.count == 0 or settings.coverage == 0:
		cover_texture = null
		return
	var extent: Vector2 = terrain.display_size()
	var budget := mini(MAX_ATTEMPTS,int(settings.count)*12)
	var columns := clampi(ceili(sqrt(budget*extent.x/extent.y)),1,budget)
	var rows := maxi(1,budget/columns)
	var cells := columns*rows
	var seed_text: String = terrain.map_seed+"/forest/"+str(int(settings.variation))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_text.hash()
	var stride := rng.randi_range(1,cells)
	while _gcd(stride,cells) != 1: stride = stride%cells+1
	var first := rng.randi_range(0,cells-1)
	var patch := FastNoiseLite.new()
	patch.seed = int(seed_text.hash() & 0x7fffffff)
	patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch.fractal_type = FastNoiseLite.FRACTAL_FBM
	patch.frequency = 5.0
	patch.fractal_octaves = 3
	var scale_factor := minf(maxf(extent.x,extent.y)/192.0,minf(extent.x,extent.y)/20.0)
	var buckets: Dictionary = {}
	var occupied: Dictionary = {}
	var spacing: float = scale_factor*settings.size*1.2*0.6
	var transforms: Array[Transform3D] = []
	var custom := PackedColorArray()
	for visit in range(cells):
		if positions.size() >= int(settings.count): break
		attempts += 1
		var cell := (first+visit*stride)%cells
		rng.seed = (seed_text+"/"+str(cell)).hash()
		var uv := (Vector2(cell%columns,cell/columns)+Vector2(rng.randf_range(0.18,0.82),rng.randf_range(0.18,0.82)))/Vector2(columns,rows)
		var cover := patch.get_noise_2d(uv.x*3.0,uv.y*3.0)*0.5+0.5
		if settings.coverage < 100 and cover < lerpf(0.64,0.36,settings.coverage/100.0): continue
		var size: float = scale_factor*settings.size*rng.randf_range(0.75,1.2)
		var location := uv*extent
		var bin := Vector2i((location/spacing).floor())
		var crowded := false
		for y in range(-1,2):
			for x in range(-1,2):
				for neighbor in occupied.get(bin+Vector2i(x,y),[]):
					if (positions[neighbor]*extent).distance_to(location) < (scales[neighbor]+size)*0.28: crowded = true
		if crowded: continue
		var site: Vector2 = terrain.map_renderer.forest_site(uv,size*0.34+scale_factor*0.12)
		if site.x < 0 or site.x >= ceiling or site.y > max_slope: continue
		var kind := 1 if rng.randf() < smoothstep(0.35,0.8,site.x)*0.75+0.12 else 0
		var index := positions.size()
		if not occupied.has(bin): occupied[bin] = []
		occupied[bin].append(index)
		positions.append(uv)
		kinds.append(kind)
		scales.append(size)
		transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),Vector3((uv.x-0.5)*extent.x,0,(uv.y-0.5)*extent.y)))
		custom.append(Color(uv.x,uv.y,size,rng.randf()))
		var bucket := Vector3i(mini(CHUNKS-1,int(uv.x*CHUNKS)),mini(CHUNKS-1,int(uv.y*CHUNKS)),kind)
		if not buckets.has(bucket): buckets[bucket] = []
		buckets[bucket].append(index)
	for bucket in buckets:
		var indices: Array = buckets[bucket]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.use_colors = true
		multimesh.mesh = meshes[bucket.z]
		multimesh.instance_count = indices.size()
		var rect := Rect2()
		var height := 0.0
		for i in range(indices.size()):
			var index: int = indices[i]
			multimesh.set_instance_transform(i,transforms[index])
			multimesh.set_instance_custom_data(i,custom[index])
			multimesh.set_instance_color(i,Color.WHITE)
			var origin := Vector2(transforms[index].origin.x,transforms[index].origin.z)
			rect = Rect2(origin,Vector2.ZERO) if i == 0 else rect.expand(origin)
			height = maxf(height,scales[index]*1.5)
		var instance := MultiMeshInstance3D.new()
		instance.name = "Forest_%d_%d_%d" % [bucket.x,bucket.y,bucket.z]
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.set_meta("footprint",rect.grow(height))
		instance.set_meta("height",height)
		add_child(instance)
	_build_cover(extent)
	_bounds = Vector2(INF,INF)

func _build_cover(extent: Vector2) -> void:
	# One bounded, derived mask; only rebuilt when placements change. Mips keep
	# distant crowns stable instead of shimmering as subpixel geometry.
	var dimensions := Vector2i((extent/extent[extent.max_axis_index()]*1024.0).ceil())
	dimensions = dimensions.max(Vector2i(2,2))
	var image := Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_R8)
	image.fill(Color.BLACK)
	for i in range(positions.size()):
		var center := positions[i]*Vector2(dimensions)-Vector2.ONE*0.5
		# A soft neighborhood, rather than a tiny crown dot, reads as forest
		# coverage at map scale. The ground shader clips it to dry geography.
		var radius := (Vector2.ONE*scales[i]*1.5/extent*Vector2(dimensions)).max(Vector2.ONE)
		var low := Vector2i((center-radius).floor()).max(Vector2i.ZERO)
		var high := Vector2i((center+radius).ceil()).min(dimensions-Vector2i.ONE)
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var distance := ((Vector2(x,y)-center)/radius).length()
				var strength := 1.0-smoothstep(0.25,1.0,distance)
				if strength > image.get_pixel(x,y).r: image.set_pixel(x,y,Color(strength,0,0))
	image.generate_mipmaps()
	cover_texture = ImageTexture.create_from_image(image)
static func _gcd(a: int,b: int) -> int:
	while b != 0:
		var next := a%b
		a = b
		b = next
	return a
