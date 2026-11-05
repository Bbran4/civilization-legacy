extends RefCounted
## Shared terrain presentation for authoring and runtime maps; no editor dependency.
const Texturing = preload("res://scripts/domain/terrain_texturing.gd")
const TextureLibrary = preload("res://scripts/rendering/procedural_ground_textures.gd")
const Regions = preload("res://scripts/domain/world_regions.gd")
const Lighting = preload("res://scripts/rendering/map_lighting.gd")
var lighting := Lighting.new()
var regions: RefCounted
var _ground_library: RefCounted
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const Patches = preload("res://scripts/rendering/terrain_patches.gd")
var patches: RefCounted
var chunking_enabled := true
var _relief_materials: Array[WeakRef] = []
const DisplayField = preload("res://scripts/rendering/display_height_field.gd")
const MAX_RELIEF_CELLS = DisplayField.MAX_RELIEF_CELLS
const BACKGROUND_THRESHOLD = (MAX_RELIEF_CELLS+1)*(MAX_RELIEF_CELLS+1)
var display_heights := PackedFloat32Array()
var display_texture: ImageTexture
var display_builds := 0
var display_cache_hits := 0
var display_prepare_usec := 0
var display_upload_usec := 0
var _height_revision := 0
var _update_depth := 0
var _display_key := ""
var _published_key := ""
var _display_cache: Array[RefCounted] = []
var _display_task := -1
var _display_job: RefCounted
var _queued_display: RefCounted
const Borders = preload("res://scripts/rendering/province_border_renderer.gd")
var borders: RefCounted
var map_extent := Vector2.ONE
const SHADER = preload("res://scripts/rendering/terrain_map.gdshader")
var surface: MeshInstance3D
var material := ShaderMaterial.new()
var shaded_relief := true
var provinces_visible := false
var _province_kinds: ImageTexture
var _nation_colors: ImageTexture
var _nation_source: RefCounted
var _nation_revision := -1
var _base_texture: ImageTexture
var rendered_heights := PackedFloat32Array()
var normalized_heights := PackedFloat32Array()
var mesh_heights := PackedFloat32Array()
var mesh_size := Vector2i.ZERO
var mesh_bounds := Vector2.ZERO
var relief := 0.0
var visible_relief := 0.0
var _relief_mesh: PlaneMesh
var _overview_mesh: PlaneMesh
var _mesh_extent := Vector2.ZERO
var _forest_clearance := PackedInt32Array()
var _forest_clearance_dirty := true
var _forest_input_valid := true
var _forest_mask_key := ""
var _height_size := Vector2i.ZERO
var _height_offset := 0.0
var _elevation := 1.0
var _datum := 0.2
var _relief_texture: ImageTexture
var _surface_layer: RefCounted
var _water_layer: RefCounted
var _water_visible := false
var _relief_dirty := true

func _init(target: MeshInstance3D) -> void:
	surface = target
	material.shader = SHADER
	lighting.bind(material)
	borders = Borders.new(surface)
	patches = Patches.new(surface,material)
	surface.material_override = material

func set_heightfield(samples: PackedFloat32Array, size: Vector2i, extent: Vector2, height_offset: float, elevation: float, generator_version: int) -> void:
	assert(samples.size() == size.x * size.y and elevation > 0.0)
	normalized_heights.resize(samples.size())
	for i in range(samples.size()):
		normalized_heights[i] = clampf((samples[i] - height_offset) / elevation + (0.2 if generator_version >= 3 else 0.0), 0.0, 1.0)
	_height_revision += 1
	_display_cache.clear()
	map_extent = extent
	_height_size = size
	_forest_clearance_dirty = true
	_height_offset = height_offset
	_elevation = elevation
	material.set_shader_parameter("ground_height_scale",elevation*maxf(extent.x,extent.y)/192.0)
	_datum = 0.2 if generator_version >= 3 else 0.0
	_relief_dirty = true
	_surface_layer = null
	_water_layer = null
	_forest_mask_key = ""
	_water_visible = false
	surface.material_override = material
	_base_texture = ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, normalized_heights.to_byte_array()))
	material.set_shader_parameter("geography_heights",_base_texture)
	borders.set_geography(_base_texture)
	set_terrain_surface(null, false)
	material.set_shader_parameter("texel_size", Vector2.ONE / Vector2(size))
	set_shaded_relief(shaded_relief)
	_rebuild_relief()

func set_shaded_relief(enabled: bool) -> void:
	shaded_relief = enabled
	borders.root.visible = enabled and provinces_visible
	material.set_shader_parameter("shaded_relief", enabled)
	set_relief(relief)

func set_water_layer(layer: RefCounted, enabled: bool) -> void:
	var mask_key: String = layer.hydraulic_fingerprint() if layer != null else ""
	if mask_key != _forest_mask_key or _water_layer != layer:
		_relief_dirty = true
		_forest_mask_key = mask_key
		_forest_clearance_dirty = true
	if _water_layer != layer or _water_visible != enabled:
		_water_layer = layer
		_water_visible = enabled
		_relief_dirty = true
	material.set_shader_parameter("water_enabled", enabled and layer != null)
	var water_texture: Texture2D = layer.texture() if layer != null else null
	material.set_shader_parameter("water_field",water_texture)
	material.set_shader_parameter("geography_water",water_texture)
	material.set_shader_parameter("geography_has_water",layer != null)
	borders.set_water(water_texture)
	_rebuild_relief()

func set_height_layer_visible(enabled: bool) -> void:
	material.set_shader_parameter("height_enabled", enabled)

func set_terrain_surface(layer: RefCounted, enabled: bool) -> void:
	var active: RefCounted = layer if enabled else null
	if active != _surface_layer:
		_surface_layer = active
		_relief_dirty = true
	rendered_heights = active.heights if active != null else normalized_heights
	material.set_shader_parameter("height_field", layer.texture() if enabled and layer != null else _base_texture)
	_rebuild_relief()

func set_provinces(layer: RefCounted, enabled: bool, preview: bool = false) -> void:
	if enabled and layer != null:
		_update_nation_colors(layer)
	provinces_visible = enabled and layer != null and not preview
	borders.update(layer,map_extent,provinces_visible and shaded_relief)
	material.set_shader_parameter("vector_borders",enabled and layer != null and not preview)
	material.set_shader_parameter("provinces_enabled", enabled)
	material.set_shader_parameter("province_field", layer.texture() if enabled else null)
	_bind_patch_materials()

func _update_nation_colors(layer: RefCounted) -> void:
	if _nation_source == layer and _nation_revision == layer.border_revision: return
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
	var kinds := Image.create(256,256,false,Image.FORMAT_R8)
	kinds.fill(Color(0,0,0))
	image.fill(Color(0,0,0,0))
	for record in layer.records:
		if record.kind != "land":
			kinds.set_pixel(record.id % 256,record.id / 256,Color(1,0,0))
			continue
		var color: Color = layer.nation_color(int(record.get("nation_id",0)))
		if color.a > 0.0: image.set_pixel(record.id % 256,record.id / 256,color)
	if _nation_colors == null: _nation_colors = ImageTexture.create_from_image(image)
	else: _nation_colors.update(image)
	if _province_kinds == null: _province_kinds = ImageTexture.create_from_image(kinds)
	else: _province_kinds.update(kinds)
	material.set_shader_parameter("province_kinds",_province_kinds)
	_nation_source = layer
	_nation_revision = layer.border_revision
	material.set_shader_parameter("nation_colors",_nation_colors)

func set_border_appearance(settings: Dictionary) -> void:
	borders.configure(settings)
	material.set_shader_parameter("smooth_borders",settings.smooth)
	material.set_shader_parameter("coast_width",settings.ocean_width)
	material.set_shader_parameter("coast_distant_scale",settings.distant_scale)

func set_paint(layer: RefCounted, enabled: bool) -> void:
	material.set_shader_parameter("paint_enabled",enabled and layer != null)
	material.set_shader_parameter("paint_field",layer.texture if layer != null else null)

func set_forest_overview(cover: Texture2D, amount: float, enabled: bool) -> void:
	material.set_shader_parameter("forest_cover",cover)
	material.set_shader_parameter("forest_overview",amount)
	material.set_shader_parameter("forest_enabled",enabled and cover != null)

func set_relief(amount: float) -> void:
	relief = clampf(amount,0.0,1.0)
	visible_relief = relief if shaded_relief and relief > 0.001 else 0.0
	var visible := visible_relief
	var detailed: bool = patches.enabled and chunking_enabled and visible > 0.0
	patches.root.visible = detailed
	if _relief_mesh != null: surface.mesh = null if detailed else (_relief_mesh if visible > 0.0 else _overview_mesh)
	material.set_shader_parameter("relief_amount",visible)
	borders.set_relief(_relief_texture,visible)
	_bind_patch_materials()

# Bilinear texture sampling uses texel centers, unlike Grid.sample's triangle mesh.
static func _texture_sample(values: PackedFloat32Array, size: Vector2i, uv: Vector2) -> float:
	return DisplayField.sample(values,size,uv)

func begin_update() -> void:
	_update_depth += 1
func end_update(background: bool = false) -> void:
	assert(_update_depth > 0)
	_update_depth -= 1
	if _update_depth == 0: _rebuild_relief(background)
func display_pending() -> bool:
	return _published_key != _display_key
func _rebuild_relief(background: bool = false) -> void:
	if _update_depth > 0 or not _relief_dirty or rendered_heights.is_empty(): return
	_relief_dirty = false
	var water: bool = _water_visible and _water_layer != null and _water_layer.has_hydraulic_data()
	_display_key = str(_height_revision)+"/"+str(_surface_layer.get_instance_id() if _surface_layer != null else 0)+"/"+(_forest_mask_key if water else "dry")
	if _published_key == _display_key:
		_queued_display = null
		surface.visible = true
		borders.root.visible = provinces_visible and shaded_relief
		return
	for cached in _display_cache:
		if cached.key == _display_key:
			display_cache_hits += 1
			_queued_display = null
			_publish_display(cached)
			return
	if _display_job != null and _display_job.key == _display_key:
		surface.visible = false
		borders.root.visible = false
		_queued_display = null
		return
	var job := DisplayField.new()
	job.key = _display_key
	job.base = rendered_heights.duplicate()
	job.size = _height_size
	job.extent = map_extent
	job.offset = _height_offset
	job.elevation = _elevation
	job.datum = _datum
	if water:
		job.mask = _water_layer.mask_bytes.duplicate()
		job.levels = _water_layer.surface_levels.duplicate()
	# Hide a stale surface while its new display is prepared. Picking is gated too.
	surface.visible = false
	borders.root.visible = false
	if background and job.base.size() > BACKGROUND_THRESHOLD:
		if _display_task >= 0: _queued_display = job
		else: _start_display(job)
	else:
		job.build()
		display_builds += 1
		_publish_display(job)
func _start_display(job: RefCounted) -> void:
	_display_job = job
	_display_task = WorkerThreadPool.add_task(job.build)
func poll_display() -> bool:
	if _display_task < 0 or not WorkerThreadPool.is_task_completed(_display_task): return false
	WorkerThreadPool.wait_for_task_completion(_display_task)
	_display_task = -1
	display_builds += 1
	var job := _display_job
	_display_job = null
	var published: bool = job.key == _display_key
	if published: _publish_display(job)
	if _queued_display != null:
		var next := _queued_display
		_queued_display = null
		if next.key == _display_key and next.key != _published_key: _start_display(next)
	return published
func _publish_display(job: RefCounted) -> void:
	var started := Time.get_ticks_usec()
	# Both textures publish atomically on the main thread from the same CPU result.
	display_heights = job.heights
	var display_image := Image.create_from_data(job.size.x,job.size.y,false,Image.FORMAT_RF,display_heights.to_byte_array())
	if display_texture == null or display_texture.get_size() != Vector2(job.size): display_texture = ImageTexture.create_from_image(display_image)
	else: display_texture.update(display_image)
	material.set_shader_parameter("display_heights",display_texture)
	material.set_shader_parameter("display_sea_height",job.sea_height)
	material.set_shader_parameter("display_texel_size",Vector2.ONE/Vector2(job.size))
	if job.mesh_size != mesh_size or _relief_mesh == null or _mesh_extent != map_extent:
		mesh_size = job.mesh_size
		_mesh_extent = map_extent
		_overview_mesh = PlaneMesh.new()
		_overview_mesh.size = map_extent
		var plane := PlaneMesh.new()
		plane.size = map_extent
		plane.subdivide_width = mesh_size.x-2
		plane.subdivide_depth = mesh_size.y-2
		_relief_mesh = plane
	mesh_heights = job.mesh_heights
	mesh_bounds = job.bounds
	var image := Image.create_from_data(mesh_size.x,mesh_size.y,false,Image.FORMAT_RF,mesh_heights.to_byte_array())
	if _relief_texture == null or _relief_texture.get_size() != Vector2(mesh_size): _relief_texture = ImageTexture.create_from_image(image)
	else: _relief_texture.update(image)
	material.set_shader_parameter("relief_vertices",_relief_texture)
	material.set_shader_parameter("map_extent",map_extent)
	var low := minf(0,mesh_bounds.x)-1.0
	var high := maxf(0,mesh_bounds.y)+1.0
	surface.custom_aabb = AABB(Vector3(-map_extent.x*0.5,low,-map_extent.y*0.5),Vector3(map_extent.x,high-low,map_extent.y))
	borders.set_relief_margin(maxf(absf(low),absf(high)))
	patches.configure(display_heights,job.size,map_extent,job.sea_height,display_texture,mesh_bounds)
	borders.set_relief_grid(surface_grid_size())
	_published_key = job.key
	_display_cache.append(job)
	while _display_cache.size() > 2: _display_cache.pop_front()
	display_prepare_usec = job.elapsed_usec
	set_relief(relief)
	if borders.source != null: borders.update(borders.source,map_extent,provinces_visible and shaded_relief)
	surface.visible = true
	borders.root.visible = provinces_visible and shaded_relief
	display_upload_usec = Time.get_ticks_usec()-started

func visible_height(uv: Vector2) -> float:
	if not shaded_relief or mesh_heights.is_empty(): return 0.0
	if patches.enabled and chunking_enabled: return patches.sample(uv)*visible_relief
	return Grid.sample(mesh_heights,mesh_size,uv)*visible_relief

func visible_bounds() -> Vector2:
	return mesh_bounds*visible_relief if shaded_relief else Vector2.ZERO

func set_texturing(settings: Dictionary, world_seed: String, visible: bool, regional_controls: RefCounted = null) -> String:
	var error := Texturing.validate(settings)
	if not error.is_empty(): return error
	# Regions are shared with forests even when the ground appearance is hidden.
	if regional_controls != null:
		regions = regional_controls.field(world_seed)
	elif regions == null or regions.seed_text != world_seed:
		regions = Regions.new(world_seed)
	material.set_shader_parameter("ground_regions",regions.texture)
	material.set_shader_parameter("region_lapse",Regions.LAPSE)
	material.set_shader_parameter("region_snow_cooling",Regions.SNOW_COOLING)
	var enabled: bool = settings.enabled and visible
	material.set_shader_parameter("textures_enabled",enabled)
	if not enabled: return ""
	var key := world_seed+"/"+str(int(settings.variation))
	if _ground_library == null or _ground_library.key != key:
		_ground_library = TextureLibrary.new(world_seed,int(settings.variation))
		for kind in _ground_library.textures: material.set_shader_parameter("ground_"+kind,_ground_library.textures[kind])
	material.set_shader_parameter("ground_scale",settings.scale)
	material.set_shader_parameter("ground_grass_cover",settings.grass_cover/100.0)
	material.set_shader_parameter("ground_rock_slope",tan(deg_to_rad(settings.rock_angle)))
	material.set_shader_parameter("ground_snow_line",settings.snow_height/100.0)
	return ""

func surface_grid_size() -> Vector2i:
	return patches.full_grid_size() if patches.enabled and chunking_enabled else mesh_size
func set_chunking_enabled(enabled: bool) -> void:
	chunking_enabled = enabled
	borders.set_relief_grid(surface_grid_size())
	if borders.source != null: borders.update(borders.source,map_extent,provinces_visible and shaded_relief)
	set_relief(relief)
func update_detail(camera: Camera3D,world_focus: Vector3) -> void:
	if not patches.enabled or not chunking_enabled: return
	var center := surface.to_local(world_focus)
	var viewport := surface.get_viewport().get_visible_rect().size
	patches.update_view(Vector2(center.x,center.z),camera.size,viewport.y,viewport.x/maxf(1,viewport.y),absf(camera.global_basis.z.y))
	_bind_patch_materials()
func _bind_patch_materials() -> void:
	material.set_shader_parameter("terrain_inverse",surface.global_transform.affine_inverse())
	patches.bind(material,chunking_enabled)
	for i in range(_relief_materials.size()-1,-1,-1):
		var target: ShaderMaterial = _relief_materials[i].get_ref()
		if target == null: _relief_materials.remove_at(i)
		else: patches.bind(target,chunking_enabled)
	for child in borders.root.get_children(): patches.bind(child.material_override,chunking_enabled)
func bind_relief_material(target: ShaderMaterial) -> void:
	var found := false
	for reference in _relief_materials:
		if reference.get_ref() == target: found = true
	if not found: _relief_materials.append(weakref(target))
	patches.bind(target,chunking_enabled)
	target.set_shader_parameter("relief_vertices",_relief_texture)
	target.set_shader_parameter("relief_amount",visible_relief)
	lighting.bind(target)

func update_lighting(sun: DirectionalLight3D, environment: Environment, camera: Camera3D, focus: Vector3) -> void:
	if camera != null: update_detail(camera,focus)
	lighting.update(sun,environment,camera,focus)
	lighting.bind(material)

# Return normalized elevation and physical slope, or a rejected site. Both root
# and canopy footprint use the canonical source/water facts, even if water is hidden.
func forest_site(uv: Vector2, radius: float) -> Vector2:
	_prepare_forest_clearance()
	if not _forest_input_valid: return Vector2(-1,-1)
	var span := Vector2.ONE*radius/map_extent
	if uv.x-span.x < 0 or uv.y-span.y < 0 or uv.x+span.x > 1 or uv.y+span.y > 1: return Vector2(-1,-1)
	var low := Vector2i(((uv-span)*Vector2(_height_size)-Vector2.ONE*0.5).floor()).max(Vector2i.ZERO)
	var high := Vector2i(((uv+span)*Vector2(_height_size)-Vector2.ONE*0.5).ceil()).min(_height_size-Vector2i.ONE)+Vector2i.ONE
	var stride := _height_size.x+1
	var forbidden := _forest_clearance[high.y*stride+high.x]-_forest_clearance[low.y*stride+high.x]-_forest_clearance[high.y*stride+low.x]+_forest_clearance[low.y*stride+low.x]
	if forbidden > 0: return Vector2(-1,-1)
	var delta := Vector2.ONE*maxf(0.6,radius)/map_extent
	var scale := _elevation*maxf(map_extent.x,map_extent.y)/192.0
	var dx := (_texture_sample(normalized_heights,_height_size,uv+Vector2(delta.x,0))-_texture_sample(normalized_heights,_height_size,uv-Vector2(delta.x,0)))*scale/(2.0*delta.x*map_extent.x)
	var dz := (_texture_sample(normalized_heights,_height_size,uv+Vector2(0,delta.y))-_texture_sample(normalized_heights,_height_size,uv-Vector2(0,delta.y)))*scale/(2.0*delta.y*map_extent.y)
	return Vector2(_texture_sample(normalized_heights,_height_size,uv),Vector2(dx,dz).length())

# A summed-area mask makes conservative canopy-footprint checks constant-time.
# Invalidation follows source heights and the water owner's content fingerprint,
# rather than view visibility or a resource's object identity alone.
func _prepare_forest_clearance() -> void:
	if not _forest_clearance_dirty: return
	_forest_clearance_dirty = false
	_forest_input_valid = _height_size.x >= 3 and _height_size.y >= 3 and normalized_heights.size() == _height_size.x*_height_size.y
	if _water_layer != null:
		_forest_input_valid = _forest_input_valid and _water_layer.mask_size == _height_size and _water_layer.mask_bytes.size() == normalized_heights.size()*4
	if not _forest_input_valid:
		_forest_clearance.clear()
		return
	var stride := _height_size.x+1
	_forest_clearance.resize(stride*(_height_size.y+1))
	_forest_clearance.fill(0)
	for y in range(_height_size.y):
		var row := 0
		for x in range(_height_size.x):
			var i := y*_height_size.x+x
			var wet: bool = _water_layer != null and (_water_layer.mask_bytes[i*4] > 8 or _water_layer.mask_bytes[i*4+1] > 8)
			if wet or not is_finite(normalized_heights[i]) or normalized_heights[i] <= 0.215: row += 1
			_forest_clearance[(y+1)*stride+x+1] = _forest_clearance[y*stride+x+1]+row
