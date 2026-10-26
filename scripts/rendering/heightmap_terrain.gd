@tool
extends Node3D
## A bounded heightfield whose generated mesh is rebuilt from Inspector settings.

signal climate_changed
signal vegetation_changed
signal terrain_regenerated
const SurfaceMaterials = preload("res://scripts/rendering/terrain_materials.gd")
const VegetationView = preload("res://scripts/rendering/terrain_vegetation_view.gd")
const Biomes = preload("res://scripts/domain/terrain_biomes.gd")
const Hydrology = preload("res://scripts/domain/terrain_hydrology.gd")
const HydrologyView = preload("res://scripts/rendering/terrain_hydrology_view.gd")
const Climate = preload("res://scripts/domain/terrain_climate.gd")
const Geography = preload("res://scripts/domain/terrain_geography.gd")
const GeographyView = preload("res://scripts/rendering/terrain_geography_view.gd")
const OCEAN_SHADER = preload("res://scripts/rendering/ocean.gdshader")
const GenerationProfile = preload("res://scripts/domain/terrain_generation_profile.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const TerrainLOD = preload("res://scripts/rendering/terrain_lod.gd")
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
@export var close_detail_enabled: bool = true:
	set(value):
		close_detail_enabled = value
		_request_rebuild()
@export_range(32, 256, 1) var close_detail_resolution: int = 128:
	set(value):
		close_detail_resolution = clampi(value, 32, 256)
		_request_rebuild()
@export_range(0.0, 2.0, 0.05) var micro_detail_strength: float = 0.15:
	set(value):
		micro_detail_strength = clampf(value, 0.0, 2.0)
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
var feature_scale: float = 1.0
var template_resolution: int = 192
var smoothing_passes: int = 1

@export_group("Map")
@export var map_size: Vector2 = Vector2(192.0, 144.0):
	set(value):
		map_size = value.clamp(Vector2(8.0, 8.0), Vector2(8192.0, 8192.0))
		_request_rebuild()
@export_range(16, 1024, 1) var resolution: int = 512:
	set(value):
		resolution = clampi(value, 16, 1024)
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
@export_range(-40.0, 80.0, 0.25) var sea_level: float = 0.0:
	set(value):
		sea_level = clampf(value, -40.0, 80.0)
		_request_rebuild()
@export var water_color: Color = Color("285b70"):
	set(value):
		water_color = value
		_request_rebuild()
@export var sand_color: Color = Color("c8b781"):
	set(value):
		sand_color = value
		_request_rebuild()
@export var grass_color: Color = Color("6e8951"):
	set(value):
		grass_color = value
		_request_rebuild()
@export var rock_color: Color = Color("777972"):
	set(value):
		rock_color = value
		_request_rebuild()
@export var snow_color: Color = Color("e4e6dc"):
	set(value):
		snow_color = value
		_request_rebuild()
@export_range(0.1, 10.0, 0.1) var beach_width: float = 2.0:
	set(value):
		beach_width = clampf(value, 0.1, 10.0)
		_request_rebuild()
@export_range(0.05, 0.8, 0.01) var rock_slope: float = 0.32:
	set(value):
		rock_slope = clampf(value, 0.05, 0.8)
		_request_rebuild()
## Altitude above the sea at which snow starts, independent of mesh elevation.
@export_range(0.0, 100.0, 0.5) var snow_height: float = 18.0:
	set(value):
		snow_height = clampf(value, 0.0, 100.0)
		_request_rebuild()

const TERRAIN_SHADER = preload("res://scripts/rendering/terrain.gdshader")
var height_samples := PackedFloat32Array()
var _dirty: bool = true
var _delay: float = 0.0
var _land_material: ShaderMaterial
var _regional_tint: Texture2D
var _regional_seed: String = ""
var _regional_size := Vector2.ZERO
var _recipe_samples := PackedFloat32Array()
var graph: RefCounted
var _graph_key: String = ""
var _restored_samples := PackedFloat32Array()
var _restored_size := Vector2i.ZERO
var generation_ms: float = 0.0
var generator_version: int = 4
var detail: Node3D
var biomes: RefCounted
var vegetation_view: Node3D
@export_range(0, 250000, 100) var tree_population: int = 20000
@export var tree_catalog: Resource = preload("res://assets/trees/catalog.tres")
var _biome_texture: Texture2D
var _habitat_texture: Texture2D
var _biome_field_texture: Texture2D
var hydrology: RefCounted
var hydrology_view: Node3D
var _hydrology_texture: Texture2D
var climate: RefCounted
var climate_settings: Dictionary = Climate.DEFAULTS.duplicate()
var climate_view: int = 0
var _climate_texture: Texture2D
var geography: RefCounted
var geography_view: Node3D
var source_heightmap_path: String = ""
var source_heightmap_size: Vector2i = Vector2i.ZERO
var heightmap_view: bool = false
var overview_blend: float = 0.0
var _sample_min: float = 0.0
var _sample_max: float = 0.0


func _ready() -> void:
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
	if detail != null:
		detail.reset()
	var surface: MeshInstance3D = _mesh_node("Surface")
	var water: MeshInstance3D = _mesh_node("Water")
	_dirty = false
	var source_image: Image = _source_image()
	_recipe_samples = PackedFloat32Array()
	if _restored_samples.is_empty():
		generator_version = 4
		_prepare_graph(source_image)
		_recipe_samples = graph.rasterize(sample_size(), surface_smoothing)
	if graph == null:
		geography = null
	elif geography == null or geography.source_hash != graph.source_fingerprint(surface_smoothing):
		geography = Geography.new()
		geography.generate(graph, surface_smoothing)
	_build_mesh(surface)
	_update_material(surface)
	var water_mesh := PlaneMesh.new()
	water_mesh.size = display_size() * 1.1
	var water_material: Material
	if geography != null:
		var image := Image.create_from_data(geography.contour_size.x, geography.contour_size.y, false, Image.FORMAT_RF, geography.display_heights.to_byte_array())
		var shader_material := ShaderMaterial.new()
		shader_material.shader = OCEAN_SHADER
		shader_material.set_shader_parameter("height_field", ImageTexture.create_from_image(image))
		shader_material.set_shader_parameter("map_size", map_size)
		shader_material.set_shader_parameter("water_height", (sea_level - height_offset) / elevation + 0.2)
		shader_material.set_shader_parameter("water_color", water_color)
		shader_material.set_shader_parameter("heightmap_view", heightmap_view)
		water_material = shader_material
	else:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = water_color
		plain.roughness = 0.35
		water_material = plain
	water_mesh.material = water_material
	water.mesh = water_mesh
	water.position.y = sea_level * relief_scale()
	water.visible = show_water
	if detail == null and not Engine.is_editor_hint():
		detail = TerrainLOD.new()
		detail.name = "TerrainLOD"
		add_child(detail, false, Node.INTERNAL_MODE_BACK)
	if detail != null:
		detail.build()
	if not Engine.is_editor_hint():
		if geography_view == null:
			geography_view = GeographyView.new()
			geography_view.name = "GeographyView"
			add_child(geography_view, false, Node.INTERNAL_MODE_BACK)
	_refresh_climate(true)
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0
	terrain_regenerated.emit()


func apply_climate(options: Dictionary) -> String:
	var error: String = Climate.validate(options)
	if not error.is_empty():
		return error
	if geography == null:
		return "Generate terrain to add climate cells."
	climate_settings = options.duplicate()
	_refresh_climate()
	return ""


func apply_tree_population(amount: int) -> void:
	tree_population = clampi(amount, 0, 250000)
	tree_catalog = preload("res://scripts/rendering/terrain_tree_library.gd").reload_assets(tree_catalog)
	if vegetation_view != null:
		vegetation_view.build(self)
		vegetation_view.set_overview_blend(overview_blend)
		vegetation_view.set_view(climate_view, heightmap_view)
	vegetation_changed.emit()


func _refresh_climate(rebuild_views: bool = false) -> void:
	var changed: bool = false
	if geography == null:
		climate = null
		biomes = null
		_biome_texture = null
		_habitat_texture = null
		_biome_field_texture = null
		_climate_texture = null
	elif climate == null or climate.source_hash != geography.source_hash or climate.settings != climate_settings:
		changed = true
		climate = Climate.new()
		climate.generate(geography, climate_settings)
		var image := Image.create_from_data(climate.size.x, climate.size.y, false, Image.FORMAT_RGBAF, climate.field.to_byte_array())
		_climate_texture = ImageTexture.create_from_image(image)
	_refresh_hydrology(changed, rebuild_views)
	if changed or (biomes == null and climate != null):
		biomes = Biomes.new()
		biomes.generate(climate, geography, graph, hydrology)
		if _biome_texture == null:
			_biome_texture = ImageTexture.create_from_image(biomes.image)
		_habitat_texture = ImageTexture.create_from_image(biomes.habitat_field) if biomes.habitat_field != null else null
		_biome_field_texture = ImageTexture.create_from_image(biomes.biome_field) if biomes.biome_field != null else null
	if not Engine.is_editor_hint() and (changed or rebuild_views or vegetation_view == null):
		if vegetation_view == null:
			vegetation_view = VegetationView.new()
			vegetation_view.name = "VegetationView"
			add_child(vegetation_view, false, Node.INTERNAL_MODE_BACK)
		vegetation_view.build(self)
		vegetation_view.set_overview_blend(overview_blend)
		vegetation_changed.emit()
	set_climate_view(climate_view)
	climate_changed.emit()


func _refresh_hydrology(climate_changed: bool, rebuild_views: bool) -> void:
	if climate == null or graph == null:
		hydrology = null
		_hydrology_texture = null
	else:
		if hydrology == null or hydrology.source_hash != geography.source_hash:
			hydrology = Hydrology.new()
			hydrology.build(graph, geography)
			climate_changed = true
		if not hydrology.error.is_empty():
			push_warning(hydrology.error)
			_hydrology_texture = null
		elif climate_changed:
			hydrology.apply_climate(graph, climate)
			_hydrology_texture = ImageTexture.create_from_image(hydrology.display_field(graph))
	if Engine.is_editor_hint():
		return
	if hydrology_view == null:
		hydrology_view = HydrologyView.new()
		hydrology_view.name = "HydrologyView"
		add_child(hydrology_view, false, Node.INTERNAL_MODE_BACK)
	if climate_changed or rebuild_views or hydrology == null:
		hydrology_view.build(self)
		if geography_view != null:
			geography_view.build(self)
			geography_view.set_overview_blend(overview_blend)
			geography_view.set_heightmap_view(heightmap_view)


func set_climate_view(mode: int) -> void:
	climate_view = clampi(mode, 0, 5)
	var visible_mode: int = climate_view if climate != null else 0
	for material in [_land_material, (get_node("Water") as MeshInstance3D).get_active_material(0)]:
		if material is ShaderMaterial:
			material.set_shader_parameter("climate_field", _climate_texture)
			material.set_shader_parameter("climate_mode", visible_mode)
			material.set_shader_parameter("biomes_enabled", biomes != null)
			material.set_shader_parameter("biome_palette", _biome_texture)
			material.set_shader_parameter("habitat_field", _habitat_texture)
			material.set_shader_parameter("biome_field", _biome_field_texture)
			material.set_shader_parameter("habitats_enabled", _habitat_texture != null)
			material.set_shader_parameter("drainage_field", _hydrology_texture)
			material.set_shader_parameter("hydrology_enabled", _hydrology_texture != null and is_equal_approx(sea_level, height_offset))
	if detail != null:
		detail.set_climate_view(visible_mode, _climate_texture, _biome_texture)
		detail.set_hydrology_field(_hydrology_texture)
		detail.set_habitat_fields(_habitat_texture, _biome_field_texture)
	if geography_view != null:
		geography_view.set_climate_view(climate_view)
	if vegetation_view != null:
		vegetation_view.set_view(climate_view, heightmap_view)
	if hydrology_view != null:
		hydrology_view.set_view(climate_view, heightmap_view)


func display_size() -> Vector2:
	return map_size


func relief_scale() -> float:
	# Scale horizontal and vertical dimensions together, preserving slopes.
	return maxf(map_size.x, map_size.y) / 192.0


func effective_graph_points() -> int:
	return clampi(roundi(graph_points * map_size.x * map_size.y / 1048576.0), 1000, 100000) if auto_density else graph_points


func height_bounds() -> Vector2:
	var bounds: Vector2 = Vector2(_sample_min, _sample_max) * relief_scale()
	if detail != null and detail.active:
		bounds.x = minf(bounds.x, detail.bounds.x)
		bounds.y = maxf(bounds.y, detail.bounds.y)
	if show_water:
		bounds.x = minf(bounds.x, sea_level * relief_scale())
		bounds.y = maxf(bounds.y, sea_level * relief_scale())
	return bounds


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


func set_overview_blend(value: float) -> void:
	if vegetation_view != null:
		vegetation_view.set_overview_blend(value)
	overview_blend = clampf(value, 0.0, 1.0)
	if _land_material != null:
		_land_material.set_shader_parameter("overview_blend", overview_blend)
	if detail != null:
		detail.set_overview_blend(overview_blend)
	if geography_view != null:
		geography_view.set_overview_blend(overview_blend)


func set_heightmap_view(enabled: bool) -> void:
	heightmap_view = enabled
	if vegetation_view != null:
		vegetation_view.set_view(climate_view, enabled)
	if hydrology_view != null:
		hydrology_view.set_view(climate_view, enabled)
	if _land_material != null:
		_land_material.set_shader_parameter("heightmap_view", enabled)
	if detail != null:
		detail.set_heightmap_view(enabled)
	if geography_view != null:
		geography_view.set_heightmap_view(enabled)
	var water := get_node_or_null("Water") as MeshInstance3D
	if water != null and water.mesh != null:
		var material: Material = water.get_active_material(0)
		if material is ShaderMaterial:
			material.set_shader_parameter("heightmap_view", enabled)


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


func _update_material(surface: MeshInstance3D) -> void:
	if _land_material == null:
		_land_material = ShaderMaterial.new()
		_land_material.shader = TERRAIN_SHADER
	SurfaceMaterials.bind_library(_land_material)
	if _regional_tint == null or _regional_seed != map_seed or _regional_size != map_size:
		_regional_tint = SurfaceMaterials.regional_field(map_size, map_seed)
		_regional_seed = map_seed
		_regional_size = map_size
	_land_material.set_shader_parameter("regional_tint", _regional_tint)
	_land_material.set_shader_parameter("map_size", display_size())
	_land_material.set_shader_parameter("sea_level", sea_level * relief_scale())
	_land_material.set_shader_parameter("height_scale", elevation * relief_scale())
	_land_material.set_shader_parameter("sand_color", sand_color)
	_land_material.set_shader_parameter("grass_color", grass_color)
	_land_material.set_shader_parameter("rock_color", rock_color)
	_land_material.set_shader_parameter("snow_color", snow_color)
	_land_material.set_shader_parameter("beach_width", beach_width)
	_land_material.set_shader_parameter("rock_slope", rock_slope)
	_land_material.set_shader_parameter("snow_height", snow_height * relief_scale())
	_land_material.set_shader_parameter("height_offset", (height_offset - elevation * 0.2 if generator_version >= 3 else height_offset) * relief_scale())
	_land_material.set_shader_parameter("terrain_lod", false)
	_land_material.set_shader_parameter("heightmap_view", heightmap_view)
	_land_material.set_shader_parameter("overview_blend", overview_blend)
	surface.material_override = _land_material


func cell_info(cell: int) -> Dictionary:
	if graph == null or cell < 0 or cell >= graph.count:
		return {}
	var info := {"id": cell, "position": graph.points[cell], "height": int(graph.heights[cell]),
		"land": graph.heights[cell] >= 20, "neighbor_count": graph.neighbors[cell].size(),
		"area": graph.cell_area(cell), "polygon": graph.polygon(cell)}
	if geography != null:
		info.merge(geography.cell_info(cell))
	if climate != null:
		info.merge(climate.cell_info(graph.points[cell] / map_size))
	if hydrology != null and hydrology.error.is_empty():
		info.merge(hydrology.cell_info(cell))
		info["flow_strength"] = info.discharge / hydrology.river_threshold
	if biomes != null and biomes.canopy.size() == graph.count:
		info.merge(biomes.native_cell_info(cell), true)
	elif climate != null:
		info.merge(Biomes.cell_info(info.temperature, info.rainfall, info.land), true)
	if vegetation_view != null and vegetation_view.layout != null and vegetation_view.layout.counts.size() == graph.count:
		info["tree_count"] = vegetation_view.layout.counts[cell]
	return info


func surface_height(uv: Vector2) -> float:
	return detail.height_at(uv) if detail != null and detail.contains(uv) else base_surface_height(uv)


func visible_surface_height(uv: Vector2) -> float:
	var height: float = surface_height(uv)
	if not show_water:
		return height
	if hydrology == null or not hydrology.error.is_empty() or heightmap_view or not is_equal_approx(sea_level, height_offset):
		return maxf(height, sea_level * relief_scale())
	var cell: int = graph.nearest_cell(uv * map_size)
	if hydrology.ocean[cell]:
		return maxf(height, sea_level * relief_scale())
	var lake_id: int = hydrology.lake_ids[cell]
	if climate_view == 0 and lake_id >= 0 and hydrology.lakes[lake_id].active:
		var lake_height: float = (height_offset + (hydrology.lakes[lake_id].level / 100.0 - 0.2) * elevation) * relief_scale()
		return maxf(height, lake_height)
	return height


func base_surface_height(uv: Vector2) -> float:
	return Grid.sample(height_samples, sample_size(), uv) * relief_scale()


func pick_cell(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	if graph == null:
		return {}
	var point: Variant = ray_surface_hit(ray_origin, ray_direction)
	if point == null:
		return {}
	var local: Vector3 = to_local(point)
	return cell_info(graph.nearest_cell(Vector2(local.x, local.z) + map_size * 0.5))


func ray_surface_hit(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	if height_samples.is_empty():
		return null
	var origin: Vector3 = to_local(ray_origin)
	var direction: Vector3 = global_transform.basis.inverse() * ray_direction
	var extent: Vector2 = display_size()
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
	var steps: int = resolution * 2 + 16
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
