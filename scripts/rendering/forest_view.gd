extends Node3D
const Meshes = preload("res://scripts/rendering/forest_meshes.gd")
const Species = preload("res://scripts/domain/tree_species.gd")
const Settings = preload("res://scripts/domain/forest_settings.gd")
const Regions = preload("res://scripts/domain/world_regions.gd")
const MAX_ATTEMPTS = 160000
const CHUNKS = 4
var material := ShaderMaterial.new()
var meshes: Array[ArrayMesh] = Meshes.library()
var shape_bounds: Array[Vector2] = []
var max_radius := 0.0
var species_counts := PackedInt32Array()
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
	material.set_shader_parameter("max_height_factor",Meshes.MAX_HEIGHT_FACTOR)
	material.set_shader_parameter("max_width_factor",Meshes.MAX_WIDTH_FACTOR)
	material.set_shader_parameter("bend_amount",Meshes.BEND)
	material.set_shader_parameter("wind_amount",Meshes.WIND)
	for mesh in meshes:
		var bounds := Meshes.bounds(mesh)
		shape_bounds.append(bounds)
		max_radius = maxf(max_radius,bounds.x)
	species_counts.resize(Species.NAMES.size())
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
	next_key += "/"+terrain.map_renderer.regions.key
	if next_key != key:
		_build(terrain,ceiling,tan(deg_to_rad(slope)))
		key = next_key
	update_presentation(terrain)
func update_presentation(terrain: Node) -> void:
	visible = terrain.tree_settings.enabled and terrain.tree_layer_visible and terrain.shaded_relief and terrain.region_preview == 0 and not terrain.map_renderer.display_pending()
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
	species_counts.fill(0)
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
	var spacing: float = scale_factor*settings.size*1.3*0.84
	var transforms: Array[Transform3D] = []
	var custom := PackedColorArray()
	var planted_slots := 0
	for visit in range(cells):
		if planted_slots >= int(settings.count): break
		attempts += 1
		var cell := (first+visit*stride)%cells
		rng.seed = (seed_text+"/"+str(cell)).hash()
		var uv := (Vector2(cell%columns,cell/columns)+Vector2(rng.randf_range(0.18,0.82),rng.randf_range(0.18,0.82)))/Vector2(columns,rows)
		var cover := patch.get_noise_2d(uv.x*3.0,uv.y*3.0)*0.5+0.5
		if settings.coverage < 100 and cover < lerpf(0.64,0.36,settings.coverage/100.0): continue
		var size: float = scale_factor*settings.size*rng.randf_range(0.70,1.3)
		var location := uv*extent
		var bin := Vector2i((location/spacing).floor())
		var crowded := false
		for y in range(-1,2):
			for x in range(-1,2):
				for neighbor in occupied.get(bin+Vector2i(x,y),[]):
					if Vector2(neighbor.x,neighbor.y).distance_to(location) < (neighbor.z+size)*0.42: crowded = true
		if crowded: continue
		var site: Vector2 = terrain.map_renderer.forest_site(uv,size*max_radius+scale_factor*0.12)
		if site.x < 0 or site.x >= ceiling or site.y > max_slope: continue
		# Geometry-based slots and spacing are independent of climate acceptance.
		# Editing a region changes only its trees, never reassigns distant slots.
		if not occupied.has(bin): occupied[bin] = []
		occupied[bin].append(Vector3(location.x,location.y,size))
		planted_slots += 1
		var region: Vector2 = terrain.map_renderer.regions.sample(uv,site.x)
		var local_ceiling: float = settings.tree_line/100.0-(1.0-region.x)*0.1
		if terrain.texture_settings.enabled and terrain.texture_settings.snow_height < 100.0:
			local_ceiling = minf(local_ceiling,terrain.texture_settings.snow_height/100.0-(1.0-region.x)*Regions.SNOW_COOLING-0.04)
		if site.x >= local_ceiling: continue
		var suitability := smoothstep(0.1,0.6,region.y)*smoothstep(0.05,0.3,region.x)
		if rng.randf() > lerpf(0.12,1.0,suitability): continue
		var kind := Species.choose(region,site.x,rng.randf())
		var index := positions.size()
		positions.append(uv)
		kinds.append(kind)
		species_counts[kind] += 1
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
		var radius := 0.0
		for i in range(indices.size()):
			var index: int = indices[i]
			multimesh.set_instance_transform(i,transforms[index])
			multimesh.set_instance_custom_data(i,custom[index])
			multimesh.set_instance_color(i,Color.WHITE)
			var origin := Vector2(transforms[index].origin.x,transforms[index].origin.z)
			rect = Rect2(origin,Vector2.ZERO) if i == 0 else rect.expand(origin)
			height = maxf(height,scales[index]*shape_bounds[bucket.z].y)
			radius = maxf(radius,scales[index]*shape_bounds[bucket.z].x)
		var instance := MultiMeshInstance3D.new()
		instance.name = "Forest_%d_%d_%d" % [bucket.x,bucket.y,bucket.z]
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.set_meta("footprint",rect.grow(radius))
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
