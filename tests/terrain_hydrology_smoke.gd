extends SceneTree
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Geography = preload("res://scripts/domain/terrain_geography.gd")
const Hydrology = preload("res://scripts/domain/terrain_hydrology.gd")
const Climate = preload("res://scripts/domain/terrain_climate.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
var failures: int = 0

class UniformClimate:
	extends RefCounted
	var rainfall: float = 1500.0
	func cell_info(_uv: Vector2) -> Dictionary:
		return {"rainfall": rainfall, "temperature": 15.0}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _height(uv: Vector2, kind: String) -> float:
	match kind:
		"ocean": return 0.1
		"flat": return 0.6
		"slope": return 0.8 - uv.x * 0.7
		"bowl":
			if uv.x > 0.91:
				return 0.1
			var radius: float = (uv - Vector2(0.5, 0.5)).length()
			var height: float = 0.25 + 0.43 * smoothstep(0.17, 0.38, radius)
			return minf(height, 0.47) if uv.x > 0.6 and absf(uv.y - 0.5) < 0.055 else height
		"nested":
			var h: float = 0.65 - uv.x * 0.3
			h -= 0.28 * exp(-pow((uv - Vector2(0.3, 0.4)).length() / 0.13, 2))
			h -= 0.24 * exp(-pow((uv - Vector2(0.65, 0.6)).length() / 0.15, 2))
			return 0.1 if uv.x > 0.94 else h
	return 0.4


func _run() -> void:
	if OS.get_cmdline_user_args().has("--large"):
		await _large()
		quit(0 if failures == 0 else 1)
		return
	var graph = Graph.new()
	graph.generate(Vector2(256, 192), 1000, "hydrology")
	var climate = UniformClimate.new()
	for kind in ["ocean", "flat", "slope", "bowl", "nested"]:
		var geography = Geography.new()
		geography.map_size = graph.map_size
		geography.contour_size = Grid.sample_size_for(graph.map_size, 128)
		geography.source_hash = kind
		geography.display_heights.resize(geography.contour_size.x * geography.contour_size.y)
		for y in range(geography.contour_size.y):
			for x in range(geography.contour_size.x):
				geography.display_heights[y * geography.contour_size.x + x] = _height(Vector2(x, y) / Vector2(geography.contour_size - Vector2i.ONE), kind)
		for cell in range(graph.count):
			graph.heights[cell] = roundi(_height(graph.points[cell] / graph.map_size, kind) * 100.0)
		var original: PackedByteArray = graph.heights.duplicate()
		var hydro = Hydrology.new()
		hydro.build(graph, geography)
		_check(hydro.error.is_empty(), kind + ": " + hydro.error)
		if not hydro.error.is_empty():
			continue
		climate.rainfall = 1500.0
		hydro.apply_climate(graph, climate)
		_check(graph.heights == original, "Drainage conditioning must never edit source heights.")
		_check(absf(hydro.total_input - hydro.total_evaporation - hydro.total_export) < maxf(0.00001, hydro.total_input * 0.0000001), "Annual runoff must equal lake losses plus map/ocean discharge.")
		var basin_area: float = 0.0
		for basin in hydro.basins:
			basin_area += basin.area
		var land_area: float = 0.0
		for cell in range(graph.count):
			if hydro.ocean[cell] == 0:
				land_area += graph.cell_area(cell)
				_check(hydro.basin_ids[cell] >= 0, "Every non-ocean cell must belong to one drainage basin.")
			var receiver: int = hydro.downstream[cell]
			if receiver >= 0:
				_check(receiver in graph.neighbors[cell] and hydro.filled[receiver] <= hydro.filled[cell] + 0.00001, "Water must follow a real graph edge downhill or across a resolved flat.")
			var current: int = cell
			var steps: int = 0
			while current >= 0 and steps <= graph.count:
				current = hydro.downstream[current]
				steps += 1
			_check(steps <= graph.count, "Cell routes must terminate without cycles.")
		_check(absf(basin_area - land_area) < 0.01, "Basin areas must cover all non-ocean terrain exactly once.")
		var expected: PackedFloat64Array = hydro.runoff.duplicate()
		var expected_lakes := PackedFloat64Array()
		expected_lakes.resize(hydro.lakes.size())
		for cell in range(graph.count):
			if hydro.lake_ids[cell] >= 0:
				expected_lakes[hydro.lake_ids[cell]] += hydro.runoff[cell]
			elif hydro.downstream[cell] >= 0:
				var receiver: int = hydro.downstream[cell]
				if hydro.lake_ids[receiver] >= 0:
					expected_lakes[hydro.lake_ids[receiver]] += hydro.flow[cell]
				else:
					expected[receiver] += hydro.flow[cell]
		for lake in hydro.lakes:
			if hydro.lake_ids[lake.receiver_cell] >= 0:
				expected_lakes[hydro.lake_ids[lake.receiver_cell]] += lake.outflow
			else:
				expected[lake.receiver_cell] += lake.outflow
		for cell in range(graph.count):
			if hydro.lake_ids[cell] < 0:
				_check(absf(expected[cell] - hydro.flow[cell]) < maxf(0.00001, hydro.flow[cell] * 0.0000001), "Every confluence must collect local rainfall and all upstream river/lake discharge.")
		for lake in hydro.lakes:
			_check(absf(expected_lakes[lake.id] - lake.inflow) < maxf(0.00001, lake.inflow * 0.0000001), "Reservoir inflow must include its catchment and local rainfall exactly once.")
			_check(lake.receiver_cell >= 0 and hydro.lake_ids[lake.receiver_cell] != lake.id, "A reservoir must have an external potential spill route.")
			for cell in lake.cells:
				_check(hydro.bed[cell] < lake.level and absf(hydro.filled[cell] - lake.level) < 0.00001, "Every lake must have one horizontal water level above its bed.")
		if kind == "ocean":
			_check(hydro.lakes.is_empty() and hydro.basins.is_empty() and hydro.rivers.is_empty(), "An all-ocean map must not invent lakes, land basins or rivers.")
		if kind == "slope":
			_check(hydro.rivers.size() > 0, "Rainfall on a slope must create a downstream river network.")
		if kind == "bowl":
			_check(hydro.lakes.size() > 0, "A mountain bowl must become a lake with a spill elevation.")
			var has_high_lake: bool = false
			for lake in hydro.lakes:
				has_high_lake = has_high_lake or lake.level > 20.0
			_check(hydro.lakes[0].outlet_cell >= 0 and hydro.lakes[0].outflow > 0.0, "A well-fed lake must spill surplus water through its outlet.")
			_check(has_high_lake, "Lakes above sea level must retain their own elevation.")
			var repeat = Hydrology.new()
			repeat.build(graph, geography)
			repeat.apply_climate(graph, climate)
			_check(repeat.downstream == hydro.downstream and repeat.flow == hydro.flow and repeat.lakes == hydro.lakes and repeat.rivers == hydro.rivers, "Identical sources and rainfall must reproduce hydrology exactly.")
			climate.rainfall = 1.0
			hydro.apply_climate(graph, climate)
			var closed: bool = false
			for lake in hydro.lakes:
				closed = closed or (lake.active and lake.outlet_cell < 0)
			_check(closed, "Underfed lakes must consume inflow rather than create an outlet river.")
		climate.rainfall = 0.0
		hydro.apply_climate(graph, climate)
		_check(hydro.rivers.is_empty() and hydro.total_export == 0.0 and hydro.total_evaporation == 0.0, "Zero rainfall must not invent runoff or flowing rivers.")
		for lake in hydro.lakes:
			_check(not lake.active and lake.outlet_cell < 0, "A zero-input lake basin must be dry in the generated map.")
		print(kind, ": ", hydro.lakes.size(), " reservoirs, ", hydro.basins.size(), " basins; %.1f ms topology" % hydro.topology_ms)
	# Cover all real procedural heightmaps, not just synthetic drainage fixtures.
	for template in Recipe.PRESETS:
		Recipe.new().generate(graph, template, "hydrology-recipes")
		var generated = Geography.new()
		generated.generate(graph, 1)
		var hydro = Hydrology.new()
		hydro.build(graph, generated)
		_check(hydro.error.is_empty(), "Recipe " + template + " must produce an acyclic reservoir graph: " + hydro.error)
		if hydro.error.is_empty():
			climate.rainfall = 1500.0
			hydro.apply_climate(graph, climate)
			_check(absf(hydro.total_input - hydro.total_evaporation - hydro.total_export) < maxf(0.00001, hydro.total_input * 0.0000001), "Recipe " + template + " must conserve model runoff.")
	print("Procedural hydrology recipes checked: ", Recipe.PRESETS.size())
	# Run the real editor, climate generator, lake/river meshes and document pipeline.
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	var panel = editor.get_node("ClimatePanel")
	var image := Image.create(129, 97, false, Image.FORMAT_RGB8)
	for y in range(97):
		for x in range(129):
			var uv := Vector2(x / 128.0, y / 96.0)
			var h: float = 0.05 if (uv - Vector2(0.5, 0.5)).length() < 0.14 else _height(uv, "bowl")
			image.set_pixel(x, y, Color(h, h, h))
	var image_path := "res://.godot/hydrology-bowl.png"
	image.save_png(image_path)
	editor._dialog_action = "image"
	editor._file_selected(image_path)
	editor._controls["map_size.x"].value = 512
	editor._controls["map_size.y"].value = 384
	editor._controls["island_enabled"].button_pressed = false
	editor.apply_settings()
	var options: Dictionary = Climate.DEFAULTS.duplicate()
	options.latitude_center = 15.0
	options.latitude_span = 20.0
	options.temperature_bias = 10.0
	options.rainfall_scale = 3.0
	_check(terrain.apply_climate(options).is_empty(), "The real climate controller must recalculate hydrology.")
	var live = terrain.hydrology
	_check(live != null and live.error.is_empty() and not live.lakes.is_empty() and not live.rivers.is_empty(), "The real imported bowl must have lakes and rainfall-fed rivers.")
	var selected_lake: Dictionary = {}
	for lake in live.lakes:
		if lake.active and (selected_lake.is_empty() or lake.area > selected_lake.area):
			selected_lake = lake
	_check(not selected_lake.is_empty() and selected_lake.level > 20.0, "The scene must render a lake with its own above-sea-level surface.")
	_check(terrain.hydrology_view.lakes_mesh != null and terrain.hydrology_view.rivers_mesh != null, "Real lake and river mesh geometry must be generated.")
	var water_cell: int = selected_lake.cells[0]
	for cell in selected_lake.cells:
		if live.bed[cell] < live.bed[water_cell]:
			water_cell = cell
	var uv: Vector2 = terrain.graph.points[water_cell] / terrain.map_size
	var point: Vector2 = terrain.graph.points[water_cell] - terrain.map_size * 0.5
	var water_height: float = (terrain.height_offset + (selected_lake.level / 100.0 - 0.2) * terrain.elevation) * terrain.relief_scale()
	_check(is_equal_approx(terrain.visible_surface_height(uv), water_height), "Water picking must use the lake level instead of sea level or its submerged bed.")
	var picked: Dictionary = terrain.pick_cell(Vector3(point.x, 10000, point.y), Vector3.DOWN)
	_check(picked.id == water_cell and picked.surface_kind == "Lake" and picked.biome == "Lake water" and picked.canopy == 0 and picked.water_depth > 20.0, "Picking a lake must expose current lake and basin data.")
	var original_samples: PackedFloat32Array = terrain.height_samples.duplicate()
	var original_cells: PackedByteArray = terrain.graph.heights.duplicate()
	var mesh_id: int = terrain.detail.chunks[0].meshes[0].get_instance_id()
	var lake_mesh_id: int = terrain.hydrology_view.lakes_mesh.mesh.get_instance_id()
	var camera = world.get_node("CameraRig")
	for zoom in [1.0, 8.0, 24.0]:
		camera._zoom = zoom
		camera._apply_zoom()
		terrain.detail._process(1.0)
		_check(terrain.hydrology == live and terrain.hydrology_view.lakes_mesh.mesh.get_instance_id() == lake_mesh_id, "Camera and LOD changes must not rebuild hydrology or lake geometry.")
	panel.overlay.select(4)
	panel.overlay.item_selected.emit(4)
	_check(terrain.climate_view == 4 and terrain.detail._material.get_shader_parameter("climate_mode") == 4 and not terrain.hydrology_view.visible, "The drainage overlay must reach LOD shaders and leave basin colours visible.")
	panel.overlay.select(0)
	panel.overlay.item_selected.emit(0)
	terrain.set_heightmap_view(true)
	_check(not terrain.hydrology_view.visible, "Height display must hide lake and river presentation.")
	terrain.set_heightmap_view(false)
	_check(terrain.hydrology_view.visible, "Normal terrain must restore water presentation.")
	var path := "res://.godot/hydrology-roundtrip.terrain.json"
	_check(Document.save_file(path, terrain).is_empty(), "Hydrology maps must save through the real document pipeline.")
	var saved_flow: PackedFloat64Array = live.flow.duplicate()
	var saved_lakes: Array = live.lakes.duplicate(true)
	var dry: Dictionary = options.duplicate()
	dry.rainfall_scale = 0.0
	terrain.apply_climate(dry)
	_check(terrain.hydrology == live and live.rivers.is_empty() and terrain.hydrology_view.lakes_mesh == null and terrain.hydrology_view.rivers_mesh == null, "Dry climate must reuse drainage topology but remove generated lakes and rivers.")
	_check(terrain.cell_info(water_cell).surface_kind == "Dry lake bed" and terrain.cell_info(water_cell).biome != "Marine", "A dry enclosed depression must not retain a marine biome or fake sea surface.")
	_check(is_equal_approx(terrain.visible_surface_height(uv), terrain.surface_height(uv)), "Dry depressions below sea level must pick the exposed lake bed.")
	_check(terrain.height_samples == original_samples and terrain.graph.heights == original_cells and terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh_id, "Climate-driven water changes must preserve original terrain and prebuilt LOD meshes.")
	var loaded: Dictionary = Document.load_file(path)
	_check(loaded.ok and Document.apply(terrain, loaded.document).is_empty(), "Current hydrology documents must load successfully.")
	_check(terrain.hydrology.flow == saved_flow and terrain.hydrology.lakes == saved_lakes, "Hydrology must regenerate exactly after a real JSON/file round trip.")
	var bad: Dictionary = Document.capture(terrain)
	bad.hydrology.version = 999
	_check(not Document.apply(terrain, bad).is_empty() and terrain.hydrology.flow == saved_flow, "Unsupported hydrology versions must be rejected before changing the world.")
	var old: Dictionary = Document.capture(terrain)
	old.version = 6
	old.erase("hydrology")
	_check(Document.apply(terrain, old).is_empty() and terrain.hydrology.flow == saved_flow and terrain.height_samples == original_samples, "Version 6 maps must gain hydrology without changing their heights or climate.")
	if DisplayServer.get_name() != "headless":
		camera._reset_view()
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = camera._camera.unproject_position(Vector3(point.x, water_height, point.y))
		editor._unhandled_input(click)
		_check(editor._cell_label.text.contains("Lake basin #") and editor._cell_label.text.contains("Basin #"), "The real cell inspector must show hydrology when clicking lake water.")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/hydrology-overview.png")
		panel.overlay.select(4)
		panel.overlay.item_selected.emit(4)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/hydrology-basins.png")
		panel.overlay.select(0)
		panel.overlay.item_selected.emit(0)
		var spill_point: Vector2 = terrain.graph.points[selected_lake.spill_cell] - terrain.map_size * 0.5
		camera.position.x = spill_point.x
		camera.position.z = spill_point.y
		camera._zoom = 4.0
		camera._apply_zoom()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/hydrology-lake-close.png")
		terrain.heightmap_texture = null
		terrain.source_heightmap_path = ""
		terrain.source_heightmap_size = Vector2i.ZERO
		terrain.terrain_template = "Continents"
		terrain.map_size = Vector2(1024, 768)
		terrain.regenerate()
		editor._sync_from_terrain()
		camera._reset_view()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/hydrology-continents.png")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(image_path)
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	world.queue_free()
	await process_frame
	print("Terrain hydrology checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _large() -> void:
	var graph = Graph.new()
	graph.generate(Vector2(4096, 2048), 80000, "large-hydrology")
	Recipe.new().generate(graph, "Continents", "large-hydrology")
	var geography = Geography.new()
	geography.generate(graph, 1)
	var climate = Climate.new()
	climate.generate(geography, Climate.DEFAULTS)
	var hydro = Hydrology.new()
	hydro.build(graph, geography)
	_check(hydro.error.is_empty(), "The large map must route without cycles: " + hydro.error)
	if not hydro.error.is_empty():
		return
	hydro.apply_climate(graph, climate)
	_check(absf(hydro.total_input - hydro.total_evaporation - hydro.total_export) < hydro.total_input * 0.0000001, "The 80,000-cell map must conserve annual model runoff.")
	for cell in range(graph.count):
		var receiver: int = hydro.downstream[cell]
		if receiver >= 0:
			_check(receiver in graph.neighbors[cell] and hydro.filled[receiver] <= hydro.filled[cell] + 0.00001, "Large-map receivers must remain neighboring, nonascending cells.")
	print("Large hydrology: ", graph.count, " cells; ", hydro.lakes.size(), " reservoirs, ", hydro.basins.size(), " basins, ", hydro.rivers.size(), " river reaches; topology %.1f ms, climate/flow %.1f ms" % [hydro.topology_ms, hydro.climate_ms])
	print("Large hydrology checks: ", "PASS" if failures == 0 else "FAIL")
