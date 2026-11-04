@tool
extends Node3D
## A bounded heightfield whose generated mesh is rebuilt from Inspector settings.

signal province_layer_changed
var province_layer: RefCounted
var province_layer_visible := false
var province_fill := true
const BorderAppearance = preload("res://scripts/domain/border_appearance.gd")
var border_appearance: Dictionary = BorderAppearance.DEFAULTS.duplicate()
signal terrain_surface_changed
signal water_layer_changed
signal terrain_regenerated
const WaterLayer = preload("res://scripts/domain/terrain_water_layer.gd")
var terrain_surface: RefCounted
var surface_layer_visible := true
var water_layer: RefCounted
var water_layer_visible := true
var height_layer_visible := true
var water_source_hash := ""
const HeightDetail = preload("res://scripts/domain/heightmap_detail.gd")
const MapRenderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
const TerrainDocument = preload("res://scripts/storage/terrain_document.gd")
const ForestSettings = preload("res://scripts/domain/forest_settings.gd")
const ForestView = preload("res://scripts/rendering/forest_view.gd")
var tree_settings: Dictionary = ForestSettings.DEFAULTS.duplicate()
var tree_layer_visible := true
var forest_view: Node3D
const Texturing = preload("res://scripts/domain/terrain_texturing.gd")
var texture_settings: Dictionary = Texturing.DEFAULTS.duplicate()
var map_paint = preload("res://scripts/domain/map_paint.gd").new()
var paint_layer_visible := true
var map_renderer: RefCounted
## Assigned before entering the tree when starting a runtime map from an editor snapshot.
var startup_document: Dictionary = {}
## Runtime authoring focus. Legacy systems remain available to explicit test fixtures.
var heightmap_only: bool = true
var coast_detail: float = 0.75
var mountain_detail: float = 0.8
var shaded_relief: bool = true


const Geography = preload("res://scripts/domain/terrain_geography.gd")
const GenerationProfile = preload("res://scripts/domain/terrain_generation_profile.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")

@export_tool_button("Regenerate terrain", "Reload") var regenerate_button: Callable = regenerate

@export_group("Heightmap Template")
@export_enum("Noise", "Volcano", "High Island", "Low Island", "Continents", "Archipelago", "Atoll", "Mediterranean", "Peninsula", "Pangea", "Isthmus", "Shattered", "Taklamakan", "Old World", "Fractious", "World heightmap", "Europe heightmap", "Mediterranean heightmap") var terrain_template: String = "Noise":
	set(value):
		terrain_template = value if value == "Noise" or Recipe.PRESETS.has(value) or Recipe.PRECREATED.has(value) else "Noise"
		_request_rebuild()
@export var map_seed: String = "42":
	set(value):
		map_seed = value.left(128) if not value.is_empty() else "42"
		_request_rebuild()
@export_range(1000, 100000, 1000) var graph_points: int = 10000:
	set(value):
		graph_points = clampi(value, 1000, 100000)
		_request_rebuild()
@export var auto_density: bool = true:
	set(value):
		auto_density = value
		_request_rebuild()
@export_range(0, 4, 1) var surface_smoothing: int = 1:
	set(value):
		surface_smoothing = clampi(value, 0, 4)
		_request_rebuild()
@export_range(0.0, 0.25, 0.005) var template_detail: float = 0.0:
	set(value):
		template_detail = clampf(value, 0.0, 0.25)
		_request_rebuild()
# Retained solely to read earlier document settings; v3 does not use these knobs.
var smoothing_passes: int = 1

@export_group("Map")
@export var map_size: Vector2 = Vector2(192.0, 144.0):
	set(value):
		map_size = value.clamp(Vector2(8.0, 8.0), Vector2(8192.0, 8192.0))
		_request_rebuild()
@export_range(16, 2049, 1) var resolution: int = 512:
	set(value):
		resolution = clampi(value, 16, 2049 if heightmap_only else 1024)
		_request_rebuild()
@export_range(1.0, 100.0, 0.5) var elevation: float = 28.0:
	set(value):
		elevation = clampf(value, 1.0, 100.0)
		_request_rebuild()
@export_range(-50.0, 50.0, 0.5) var height_offset: float = 0.0:
	set(value):
		height_offset = clampf(value, -50.0, 50.0)
		_request_rebuild()
@export_range(0.25, 4.0, 0.05) var height_contrast: float = 1.35:
	set(value):
		height_contrast = clampf(value, 0.25, 4.0)
		_request_rebuild()

@export_group("Noise")
## Expand this resource for seed, frequency, algorithm, octaves, gain and domain warp.
@export var land_noise: FastNoiseLite:
	set(value):
		if land_noise != mountain_noise:
			_disconnect_noise(land_noise)
		land_noise = value
		_connect_noise(land_noise)
		_request_rebuild()
@export var mountain_noise: FastNoiseLite:
	set(value):
		if mountain_noise != land_noise:
			_disconnect_noise(mountain_noise)
		mountain_noise = value
		_connect_noise(mountain_noise)
		_request_rebuild()
@export_range(0.0, 1.0, 0.01) var mountain_strength: float = 0.0:
	set(value):
		mountain_strength = clampf(value, 0.0, 1.0)
		_request_rebuild()
@export var noise_offset: Vector2 = Vector2.ZERO:
	set(value):
		noise_offset = value
		_request_rebuild()

@export_group("Optional Heightmap Image")
## Red-channel height: black = low, white = high. Noise works without an image.
@export var heightmap_texture: Texture2D:
	set(value):
		if heightmap_texture != null and heightmap_texture.changed.is_connected(_request_rebuild):
			heightmap_texture.changed.disconnect(_request_rebuild)
		heightmap_texture = value
		if heightmap_texture != null:
			heightmap_texture.changed.connect(_request_rebuild)
		_request_rebuild()
@export_range(0.0, 1.0, 0.01) var image_blend: float = 1.0:
	set(value):
		image_blend = clampf(value, 0.0, 1.0)
		_request_rebuild()
@export var invert_image: bool = false:
	set(value):
		invert_image = value
		_request_rebuild()

@export_group("Island Shape")
@export var island_enabled: bool = true:
	set(value):
		island_enabled = value
		_request_rebuild()
## Fraction of the map radius at which the coast starts falling toward the seabed.
@export_range(0.1, 0.95, 0.01) var island_inner_radius: float = 0.48:
	set(value):
		island_inner_radius = clampf(value, 0.1, 0.95)
		_request_rebuild()
@export_range(1.0, 8.0, 0.1) var island_roundness: float = 2.6:
	set(value):
		island_roundness = clampf(value, 1.0, 8.0)
		_request_rebuild()

@export_group("Water and Surface")
@export var show_water: bool = true:
	set(value):
		show_water = value
		_request_rebuild()
@export_group("Map Presentation")
## Presents land as a flat strategy map while retaining elevation for classification.
@export_range(-40.0, 80.0, 0.25) var sea_level: float = 0.0:
	set(value):
		sea_level = clampf(value, -40.0, 80.0)
		_request_rebuild()
@export var water_color: Color = Color("285b70"):
	set(value):
		water_color = value
		_request_rebuild()
## Altitude above the sea at which snow starts, independent of mesh elevation.

var height_samples := PackedFloat32Array()
var _dirty: bool = true
var _delay: float = 0.0
var _land_material: ShaderMaterial
var _recipe_samples := PackedFloat32Array()
var graph: RefCounted
var _graph_key: String = ""
var _restored_samples := PackedFloat32Array()
var _restored_size := Vector2i.ZERO
var generation_ms: float = 0.0
var generator_version: int = 4
var geography: RefCounted
var source_heightmap_path: String = ""
var source_heightmap_size: Vector2i = Vector2i.ZERO
var heightmap_view: bool = false
var overview_blend: float = 0.0
var _sample_min: float = 0.0
var _sample_max: float = 0.0


func _ready() -> void:
	if not startup_document.is_empty():
		var document := startup_document
		startup_document = {}
		var error: String = TerrainDocument.apply(self, document)
		if error.is_empty():
			return
		push_error("Could not load initial terrain: " + error)
	if not Engine.is_editor_hint():
		GenerationProfile.apply(self)
	regenerate()


func _process(delta: float) -> void:
	if not _dirty:
		return
	_delay -= delta
	if _delay <= 0.0:
		regenerate()


func _request_rebuild() -> void:
	_restored_samples = PackedFloat32Array()
	_dirty = true
	_delay = 0.2


func _connect_noise(noise: FastNoiseLite) -> void:
	if noise != null and not noise.changed.is_connected(_request_rebuild):
		noise.changed.connect(_request_rebuild)


func _disconnect_noise(noise: FastNoiseLite) -> void:
	if noise != null and noise.changed.is_connected(_request_rebuild):
		noise.changed.disconnect(_request_rebuild)


func regenerate() -> void:
	var started: int = Time.get_ticks_usec()
	if not is_inside_tree():
		_request_rebuild()
		return
	var surface := _mesh_node("Surface")
	var water := _mesh_node("Water")
	_dirty = false
	_recipe_samples = PackedFloat32Array()
	_regenerate_heightmap_only(surface, water, _source_image(), started)

func display_size() -> Vector2:
	return map_size


func relief_scale() -> float:
	# Scale horizontal and vertical dimensions together, preserving slopes.
	return maxf(map_size.x, map_size.y) / 192.0


func effective_graph_points() -> int:
	return clampi(roundi(graph_points * map_size.x * map_size.y / 1048576.0), 1000, 100000) if auto_density else graph_points


func height_bounds() -> Vector2:
	return map_renderer.visible_bounds() if map_renderer != null else Vector2.ZERO


func _geometry_key() -> String:
	return JSON.stringify([map_seed, map_size.x, map_size.y, effective_graph_points()])


func _prepare_graph(source_image: Image) -> void:
	var key: String = _geometry_key()
	if graph == null or key != _graph_key:
		graph = Graph.new()
		graph.generate(map_size, effective_graph_points(), map_seed)
		_graph_key = key
	var generator = Recipe.new()
	if Recipe.PRESETS.has(terrain_template):
		generator.generate(graph, terrain_template, map_seed)
	else:
		graph.heights.fill(0)
		if terrain_template == "Noise":
			var sampler: FastNoiseLite = land_noise.duplicate() if land_noise != null else FastNoiseLite.new()
			var random = preload("res://scripts/domain/alea.gd").new(map_seed)
			sampler.seed = sampler.seed ^ int(random.next() * 2147483647.0)
			for i in range(graph.count):
				var point: Vector2 = (graph.points[i] / map_size - Vector2(0.5, 0.5)) * (map_size / relief_scale()) + noise_offset
				var noise: float = sampler.get_noise_2d(point.x, point.y) if land_noise != null else 0.0
				graph.heights[i] = clampi(int((noise * 0.5 + 0.5) * 100.0), 0, 100)
	var image: Image = source_image
	if image == null and Recipe.PRECREATED.has(terrain_template):
		var texture: Texture2D = load(Recipe.PRECREATED[terrain_template])
		image = texture.get_image()
	if image != null:
		var image_heights: PackedByteArray = generator.from_image(graph, image, invert_image)
		for i in range(graph.count):
			graph.heights[i] = int(lerpf(graph.heights[i], image_heights[i], image_blend))
	# Optional edits are applied once at the cell-data boundary. Defaults execute
	# the upstream recipe unchanged, without additional directional noise.
	for i in range(graph.count):
		var uv: Vector2 = graph.points[i] / map_size
		var point: Vector2 = (uv - Vector2(0.5, 0.5)) * (map_size / relief_scale()) + noise_offset
		var value: float = graph.heights[i] / 100.0
		if template_detail > 0.0 and land_noise != null:
			value += land_noise.get_noise_2d(point.x, point.y) * template_detail
		if mountain_strength > 0.0 and mountain_noise != null:
			value += (mountain_noise.get_noise_2d(point.x, point.y) * 0.5 + 0.5) * mountain_strength * smoothstep(0.3, 0.7, value)
		value = pow(clampf(value, 0.0, 1.0), height_contrast)
		if island_enabled:
			var centered: Vector2 = (uv * 2.0 - Vector2.ONE).abs()
			var radius: float = pow(pow(centered.x, island_roundness) + pow(centered.y, island_roundness), 1.0 / island_roundness)
			value *= 1.0 - smoothstep(island_inner_radius, 1.0, radius)
		graph.heights[i] = clampi(roundi(value * 100.0), 0, 100)
	graph.invalidate_display()


func graph_snapshot() -> Dictionary:
	return graph.snapshot() if graph != null else {}


func geography_snapshot() -> Dictionary:
	return geography.snapshot() if geography != null else {}


func restore_graph(data: Dictionary) -> void:
	geography = null
	graph = null
	_graph_key = ""
	if not data.is_empty():
		graph = Graph.new()
		graph.restore(data, map_size, effective_graph_points())
		_graph_key = _geometry_key()


func _source_image() -> Image:
	if heightmap_texture == null:
		return null
	var image: Image = heightmap_texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		push_warning("Heightmap could not be decompressed; using noise instead.")
		return null
	return image


func source_image_snapshot() -> Dictionary:
	var source: Dictionary = {"path": source_heightmap_path, "red_samples": []}
	if heightmap_texture == null:
		return source
	var image: Image = _source_image()
	if image == null:
		return {"error": "The source heightmap cannot be read."}
	var samples: Array = []
	var size: Vector2i = sample_size()
	for y in range(size.y):
		for x in range(size.x):
			samples.append(_sample_image(image, Vector2(x, y) / Vector2(size - Vector2i.ONE)))
	source.red_samples = samples
	var original_size: Vector2i = source_heightmap_size if source_heightmap_size != Vector2i.ZERO else image.get_size()
	source["original_size"] = [original_size.x, original_size.y]
	if source.path.is_empty():
		source.path = heightmap_texture.resource_path
	return source


func sample_size() -> Vector2i:
	return _restored_size if not _restored_samples.is_empty() else Grid.sample_size_for(map_size, resolution)


func restore_heightfield(samples: PackedFloat32Array, size: Vector2i, version: int = 4) -> void:
	assert(samples.size() == size.x * size.y)
	generator_version = version
	_restored_size = size
	_restored_samples = samples.duplicate()
	regenerate()


func heightmap_image() -> Image:
	var size: Vector2i = sample_size()
	var width: int = size.x
	var image := Image.create(width, size.y, false, Image.FORMAT_RGB8)
	for z in range(size.y):
		for x in range(width):
			var height: float = clampf((height_samples[z * width + x] - height_offset) / elevation + (0.2 if generator_version >= 3 else 0.0), 0.0, 1.0)
			image.set_pixel(x, z, Color(height, height, height, 1.0))
	return image


func is_flat_map_mode() -> bool:
	return not shaded_relief


func _mesh_node(node_name: String) -> MeshInstance3D:
	var instance := get_node_or_null(NodePath(node_name)) as MeshInstance3D
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = node_name
		# Internal, unowned children are rebuilt rather than serialized into the scene.
		add_child(instance, false, Node.INTERNAL_MODE_BACK)
	return instance


func _build_mesh(surface: MeshInstance3D) -> void:
	var size: Vector2i = sample_size()
	var count: int = size.x * size.y
	height_samples.resize(count)
	var world_heights := PackedFloat32Array()
	world_heights.resize(count)
	_sample_min = INF
	_sample_max = -INF
	var factor: float = relief_scale()
	for i in range(count):
		var height: float = _restored_samples[i] if not _restored_samples.is_empty() else height_offset + (_recipe_samples[i] - 0.2) * elevation
		height_samples[i] = height
		world_heights[i] = height * factor
		_sample_min = minf(_sample_min, height)
		_sample_max = maxf(_sample_max, height)
	if not heightmap_only:
		surface.mesh = Grid.mesh_from_heights(world_heights, size, display_size())


func _sample_image(image: Image, uv: Vector2) -> float:
	var pixel := uv * Vector2(image.get_width() - 1, image.get_height() - 1)
	var x: int = int(pixel.x)
	var y: int = int(pixel.y)
	var next_x: int = mini(x + 1, image.get_width() - 1)
	var next_y: int = mini(y + 1, image.get_height() - 1)
	var upper: float = lerpf(image.get_pixel(x, y).r, image.get_pixel(next_x, y).r, pixel.x - x)
	var lower: float = lerpf(image.get_pixel(x, next_y).r, image.get_pixel(next_x, next_y).r, pixel.x - x)
	return clampf(lerpf(upper, lower, pixel.y - y), 0.0, 1.0)


func surface_height(uv: Vector2) -> float:
	if heightmap_only and terrain_surface_current():
		return ((Grid.sample(terrain_surface.heights, sample_size(), uv) - (0.2 if generator_version >= 3 else 0.0)) * elevation + height_offset) * relief_scale()
	return base_surface_height(uv)


func base_surface_height(uv: Vector2) -> float:
	return Grid.sample(height_samples, sample_size(), uv) * relief_scale()


func pick_cell(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	if graph == null:
		return {}
	var point: Variant = ray_surface_hit(ray_origin, ray_direction)
	if point == null:
		return {}
	var local: Vector3 = to_local(point)
	return point_info(Vector2(local.x, local.z) + map_size * 0.5)


func ray_surface_hit(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	if height_samples.is_empty():
		return null
	var origin: Vector3 = to_local(ray_origin)
	var direction: Vector3 = global_transform.basis.inverse() * ray_direction
	var extent: Vector2 = display_size()
	if map_renderer == null or map_renderer.visible_relief == 0.0:
		var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
		if hit != null and absf(hit.x) <= extent.x * 0.5 and absf(hit.z) <= extent.y * 0.5:
			return to_global(hit)
		return null
	var bounds: Vector2 = height_bounds()
	var low := Vector3(-extent.x * 0.5, minf(bounds.x, sea_level * relief_scale()) - 2.0, -extent.y * 0.5)
	var high := Vector3(extent.x * 0.5, maxf(bounds.y, sea_level * relief_scale()) + 2.0, extent.y * 0.5)
	var enter: float = 0.0
	var leave: float = 100000.0
	for axis in range(3):
		if absf(direction[axis]) < 1e-9:
			if origin[axis] < low[axis] or origin[axis] > high[axis]:
				return null
			continue
		var first: float = (low[axis] - origin[axis]) / direction[axis]
		var last: float = (high[axis] - origin[axis]) / direction[axis]
		enter = maxf(enter, minf(first, last))
		leave = minf(leave, maxf(first, last))
	if enter > leave:
		return null
	var previous_t: float = enter
	var steps: int = maxi(32,ceili(Vector2(direction.x,direction.z).length()*(leave-enter)/minf(extent.x/(map_renderer.mesh_size.x-1),extent.y/(map_renderer.mesh_size.y-1))*2.0))
	for step_index in range(steps + 1):
		var t: float = lerpf(enter, leave, float(step_index) / steps)
		var point: Vector3 = origin + direction * t
		var uv := Vector2(point.x, point.z) / extent + Vector2(0.5, 0.5)
		var height: float = visible_surface_height(uv)
		if point.y <= height:
			for refinement in range(16):
				var middle: float = (previous_t + t) * 0.5
				point = origin + direction * middle
				uv = Vector2(point.x, point.z) / extent + Vector2(0.5, 0.5)
				height = visible_surface_height(uv)
				if point.y > height:
					previous_t = middle
				else:
					t = middle
			return to_global(origin + direction * t)
		previous_t = t
	return null


func _regenerate_heightmap_only(surface: MeshInstance3D, water: MeshInstance3D, source_image: Image, started: int) -> void:
	heightmap_view = true
	water.visible = false
	if _restored_samples.is_empty():
		generator_version = 4
		_prepare_graph(source_image)
		var image := source_image
		if image == null and Recipe.PRECREATED.has(terrain_template):
			image = (load(Recipe.PRECREATED[terrain_template]) as Texture2D).get_image()
		if image != null:
			var size := sample_size()
			_recipe_samples.resize(size.x * size.y)
			for y in range(size.y):
				for x in range(size.x):
					var uv := Vector2(x, y) / Vector2(size - Vector2i.ONE)
					var h := _sample_image(image, uv)
					_recipe_samples[y * size.x + x] = 1.0 - h if invert_image else h
		else:
			_recipe_samples = HeightDetail.refine(graph.rasterize(sample_size(), surface_smoothing), sample_size(), map_seed, coast_detail, mountain_detail)
	# Retain the existing document's geographic cache contract; no climate or water
	# simulation and no geography rendering is instantiated in this workspace.
	if graph != null and (geography == null or geography.source_hash != graph.source_fingerprint(surface_smoothing)):
		geography = Geography.new()
		geography.generate(graph, surface_smoothing)
	_build_mesh(surface)
	if map_renderer == null:
		map_renderer = MapRenderer.new(surface)
	map_renderer.set_shaded_relief(shaded_relief)
	map_renderer.set_heightfield(height_samples, sample_size(), display_size(), height_offset, elevation, generator_version)
	map_renderer.set_relief(1.0-overview_blend)
	_land_material = map_renderer.material
	water_source_hash = WaterLayer.fingerprint(height_samples, sample_size(), map_size, height_offset, elevation, generator_version)
	refresh_water_layer()
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0
	terrain_regenerated.emit()

func set_shaded_relief(enabled: bool) -> void:
	shaded_relief = enabled
	if heightmap_only and map_renderer != null:
		map_renderer.set_shaded_relief(enabled)
		refresh_water_layer()
	var rig := get_parent().get_node_or_null("CameraRig")
	if rig != null and rig.is_node_ready(): rig._apply_zoom()

func set_raw_height_view(enabled: bool) -> void:
	set_shaded_relief(not enabled)

func set_relief_preview(enabled: bool) -> void:
	# Compatibility for callers of the original editor-preview API.
	set_shaded_relief(enabled)

func water_layer_current() -> bool:
	return water_layer != null and water_layer.source_hash == water_source_hash and water_layer.mask_size == sample_size()

func refresh_water_layer() -> void:
	if heightmap_only and map_renderer != null:
		map_renderer.set_texturing(texture_settings,map_seed,paint_layer_visible)
		var derived := terrain_surface_current() and surface_layer_visible and shaded_relief
		map_renderer.set_terrain_surface(terrain_surface, derived)
		map_renderer.set_paint(map_paint, paint_layer_visible)
		map_renderer.material.set_shader_parameter("province_fill", province_fill)
		map_renderer.set_border_appearance(border_appearance)
		map_renderer.set_provinces(province_layer, province_layer_visible and province_layer_current() and shaded_relief)
		map_renderer.set_height_layer_visible(height_layer_visible or derived)
		map_renderer.set_water_layer(water_layer if water_layer_current() else null, water_layer_visible and water_layer_current())
		if not Engine.is_editor_hint():
			if forest_view == null and tree_settings.enabled:
				forest_view = ForestView.new()
				forest_view.name = "GeneratedForest"
				add_child(forest_view,false,Node.INTERNAL_MODE_BACK)
			if forest_view != null: forest_view.refresh(self)

func install_water_layer(layer: RefCounted) -> String:
	if layer == null or layer.source_hash != water_source_hash or layer.mask_size != sample_size():
		return "The heightmap changed. Generate water again for the current terrain."
	water_layer = layer
	refresh_water_layer()
	water_layer_changed.emit()
	return ""

func set_water_layer_visible(enabled: bool) -> void:
	water_layer_visible = enabled
	refresh_water_layer()

func set_height_layer_visible(enabled: bool) -> void:
	height_layer_visible = enabled
	refresh_water_layer()

func terrain_surface_current() -> bool:
	return terrain_surface != null and water_layer_current() and water_layer.has_hydraulic_data() and terrain_surface.source_hash == water_source_hash and terrain_surface.water_hash == water_layer.hydraulic_fingerprint() and terrain_surface.size == sample_size()

func install_terrain_surface(layer: RefCounted) -> String:
	if layer == null or not water_layer_current() or layer.source_hash != water_source_hash or layer.water_hash != water_layer.hydraulic_fingerprint() or layer.size != sample_size():
		return "The source maps changed. Build the terrain surface again."
	var error: String = layer.validate_water(water_layer)
	if not error.is_empty():
		return error
	terrain_surface = layer
	refresh_water_layer()
	terrain_surface_changed.emit()
	return ""

func set_surface_layer_visible(enabled: bool) -> void:
	surface_layer_visible = enabled
	refresh_water_layer()

func province_layer_current() -> bool:
	return province_layer != null and terrain_surface_current() and province_layer.source_hash == terrain_surface.fingerprint() and province_layer.size == sample_size()
func install_province_layer(layer: RefCounted) -> String:
	if layer == null or not terrain_surface_current() or layer.source_hash != terrain_surface.fingerprint() or layer.size != sample_size():
		return "The terrain surface changed. Generate provinces again."
	province_layer = layer
	refresh_water_layer()
	province_layer_changed.emit()
	return ""
func set_province_layer_visible(enabled: bool) -> void:
	province_layer_visible = enabled
	refresh_water_layer()

func set_province_fill(enabled: bool) -> void:
	province_fill = enabled
	refresh_water_layer()

func set_border_appearance(settings: Dictionary) -> String:
	var error: String = BorderAppearance.validate(settings)
	if not error.is_empty(): return error
	border_appearance = settings.duplicate()
	refresh_water_layer()
	return ""

func set_overview_blend(value: float) -> void:
	overview_blend = clampf(value,0.0,1.0)
	if map_renderer != null: map_renderer.set_relief(1.0-overview_blend)
	if forest_view != null: forest_view.update_presentation(self)

func set_heightmap_view(_enabled: bool) -> void:
	heightmap_view = true

func cell_info(cell: int) -> Dictionary:
	if graph == null or cell < 0 or cell >= graph.count: return {}
	return {"id": cell, "position": graph.points[cell], "height": int(graph.heights[cell]), "land": graph.heights[cell] >= 20}

func point_info(point: Vector2) -> Dictionary:
	var info := cell_info(graph.nearest_cell(point)) if graph != null else {}
	info["inspected_position"] = point
	return info

func visible_surface_height(uv: Vector2) -> float:
	return map_renderer.visible_height(uv) if map_renderer != null else 0.0

func apply_automatic_textures(settings: Dictionary) -> String:
	var error := Texturing.validate(settings)
	if not error.is_empty(): return error
	texture_settings = settings.duplicate()
	refresh_water_layer()
	return ""

func apply_tree_settings(settings: Dictionary) -> String:
	var error := ForestSettings.validate(settings)
	if not error.is_empty(): return error
	tree_settings = settings.duplicate()
	refresh_water_layer()
	return ""
