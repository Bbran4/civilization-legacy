extends SceneTree
const Biomes = preload("res://scripts/domain/terrain_biomes.gd")
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Geography = preload("res://scripts/domain/terrain_geography.gd")
const Hydrology = preload("res://scripts/domain/terrain_hydrology.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures: int = 0

class UniformClimate:
	extends RefCounted
	var size := Vector2i(2, 2)
	var rainfall: float = 1500.0
	func cell_info(_uv: Vector2) -> Dictionary:
		return {"rainfall": rainfall, "temperature": 15.0}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_check(Biomes.habitat(25, 50, 0, 0).biome_id == 4, "Dry hot land must remain desert.")
	_check(Biomes.habitat(15, 300, 0.8, 0.01).biome_id == 13, "Flat water-supported land must support wetlands.")
	_check(Biomes.habitat(15, 100, 0.8, 0.1).biome_id == 14, "Suitable dry river banks must support riparian woodland.")
	_check(Biomes.habitat(15, 100, 0.8, 0.8).canopy == 0, "Steep cliffs must exclude canopy.")
	_check(Biomes.habitat(-5, 1000, 1, 0).biome_id == 2, "Water must not turn tundra into temperate wetland.")
	_check(Biomes.habitat(15, 1500, 1, 0, 12).canopy == 0, "Lakes must exclude terrestrial canopy.")
	var graph = Graph.new()
	graph.generate(Vector2(256, 192), 1000, "biome-routing")
	for cell in range(graph.count):
		var uv: Vector2 = graph.points[cell] / graph.map_size
		graph.heights[cell] = 10 if uv.x > 0.9 else roundi(65 - uv.x * 45)
	var geography = Geography.new()
	geography.generate(graph, 1)
	var hydro = Hydrology.new()
	hydro.build(graph, geography)
	var climate = UniformClimate.new()
	hydro.apply_climate(graph, climate)
	var biomes = Biomes.new()
	biomes.generate(climate, geography, graph, hydro)
	var original: PackedByteArray = biomes.ids.duplicate()
	var original_canopy: PackedFloat32Array = biomes.canopy.duplicate()
	var supported: int = 0
	for cell in range(graph.count):
		_check(is_finite(biomes.water_support[cell]) and biomes.canopy[cell] >= 0 and biomes.canopy[cell] <= 1, "Ecology must stay finite and bounded.")
		if hydro.ocean[cell] != 0:
			_check(biomes.ids[cell] == 0 and biomes.canopy[cell] == 0, "Ocean identity must override land climate.")
		if hydro.river_ids[cell] >= 0:
			_check(biomes.canopy[cell] == 0, "Active channel cells must exclude trees.")
		if hydro.ocean[cell] == 0 and hydro.river_ids[cell] < 0 and biomes.water_support[cell] > 0.1:
			supported += 1
	_check(supported > 0, "Actual routed rivers must influence neighboring land cells.")
	biomes.generate(climate, geography, graph, hydro)
	_check(biomes.ids == original and biomes.canopy == original_canopy, "Ecology must regenerate deterministically.")
	climate.rainfall = 0
	hydro.apply_climate(graph, climate)
	biomes.generate(climate, geography, graph, hydro)
	for value in biomes.water_support:
		_check(value == 0, "Zero-rain dry channels must not supply permanent freshwater.")
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	terrain.map_size = Vector2(256, 192)
	terrain.terrain_template = "Continents"
	terrain.regenerate()
	var saved: Dictionary = Document.capture(terrain)
	var saved_ids: PackedByteArray = terrain.biomes.ids.duplicate()
	var canopy: PackedFloat32Array = terrain.biomes.canopy.duplicate()
	var mesh: int = terrain.detail.chunks[0].meshes[0].get_instance_id()
	var panel = world.get_node("Interface/Editor/ClimatePanel")
	panel.overlay.select(5)
	panel.overlay.item_selected.emit(5)
	_check(terrain.detail._material.get_shader_parameter("climate_mode") == 5 and terrain._land_material.get_shader_parameter("habitats_enabled"), "Biomes view and ecology must reach all terrain materials.")
	_check(terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh, "Inspection must preserve prebuilt LOD meshes.")
	_check(terrain.cell_info(0).has("canopy"), "Cell inspection must expose authoritative canopy data.")
	_check(Document.validate(saved).is_empty() and saved.version == Document.VERSION, "New maps must record the biome algorithm version.")
	var bad: Dictionary = saved.duplicate(true)
	bad.biomes.version = 999
	_check(not Document.apply(terrain, bad).is_empty(), "Unknown biome algorithms must be rejected before applying a map.")
	var old: Dictionary = saved.duplicate(true)
	old.version = 7
	old.erase("biomes")
	_check(Document.apply(terrain, old).is_empty() and terrain.biomes.ids == saved_ids and terrain.biomes.canopy == canopy, "Version 7 maps must gain deterministic ecology without changing terrain.")
	if DisplayServer.get_name() != "headless":
		panel.overlay.select(5)
		panel.overlay.item_selected.emit(5)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/biome-classification.png")
		panel.overlay.select(0)
		panel.overlay.item_selected.emit(0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/biome-terrain.png")
	world.queue_free()
	await process_frame
	print("Terrain biome checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
