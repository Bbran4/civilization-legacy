extends SceneTree
const Biomes = preload("res://scripts/domain/terrain_biomes.gd")
const Climate = preload("res://scripts/domain/terrain_climate.gd")
const Geography = preload("res://scripts/domain/terrain_geography.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _fixture(ridge: bool) -> RefCounted:
	var geography = Geography.new()
	geography.map_size = Vector2(1024, 1024)
	geography.source_hash = "climate-fixture"
	geography.contour_size = Vector2i(129, 129)
	geography.display_heights.resize(129 * 129)
	for y in range(129):
		for x in range(129):
			var h: float = 0.1
			if ridge and x > 20 and x < 108:
				h = 0.3 + 0.5 * exp(-pow((x - 64.0) / 9.0, 2))
			geography.display_heights[y * 129 + x] = h
	return geography


func _run() -> void:
	for example in [[30.0, 100.0, "Hot desert"], [10.0, 100.0, "Cold desert"], [12.0, 1200.0, "Temperate forest"], [12.0, 2500.0, "Temperate rainforest"], [25.0, 2500.0, "Tropical rainforest"], [25.0, 900.0, "Savanna"], [5.0, 1000.0, "Boreal forest"], [-5.0, 500.0, "Tundra"], [-20.0, 100.0, "Ice"]]:
		_check(Biomes.NAMES[Biomes.classify(example[0], example[1])] == example[2], "Temperature/rainfall must produce " + example[2])
	_check(Biomes.classify(30, 0, false) == 0, "Water must remain Marine regardless of dry land climate.")
	_check(Biomes.classify(45, 400) == 4 and Biomes.classify(10, 400) != 4, "Hotter terrain must need more rainfall to avoid desert through evaporative demand.")
	var sea = _fixture(false)
	var options: Dictionary = Climate.DEFAULTS.duplicate()
	var climate = Climate.new()
	climate.generate(sea, options)
	_check(climate.temperature_range.y > 28.0, "Calculated temperatures must exceed 20°C; the warmth control is an offset rather than a temperature cap.")
	_check(climate.cell_info(Vector2(0.5, 0.5)).temperature > climate.cell_info(Vector2(0.5, 0.0)).temperature + 20, "The equator must be warmer than high latitudes.")
	for i in range(climate.temperature.size()):
		_check(is_finite(climate.temperature[i]) and climate.rainfall[i] >= 0 and climate.rainfall[i] <= 6000 and is_equal_approx(climate.winds[i].length(), 1.0), "Every climate sample must contain bounded finite data and a unit wind.")
	var repeat = Climate.new()
	repeat.generate(sea, options)
	_check(repeat.field == climate.field, "Identical terrain and climate choices must produce the same fields.")
	_check(Climate.wind_at(45, 0).x > 0 and Climate.wind_at(15, 0).x < 0 and Climate.wind_at(75, 0).x < 0, "Latitude bands must produce westerlies, trades and polar easterlies.")
	_check(Climate.wind_at(45, 0).dot(Climate.wind_at(45, 180)) < -0.999, "The wind dial must rotate actual prevailing winds.")
	options.latitude_span = 10.0
	options.latitude_center = 45.0
	options.wind_rotation = rad_to_deg(atan(0.35))
	var ridge = _fixture(true)
	climate.generate(ridge, options)
	var windward: Dictionary = climate.cell_info(Vector2(0.46, 0.5))
	var leeward: Dictionary = climate.cell_info(Vector2(0.62, 0.5))
	print("Ridge: windward %.0f / leeward %.0f mm/yr; %.1f / %.1f°C" % [windward.rainfall, leeward.rainfall, windward.temperature, leeward.temperature])
	_check(windward.rainfall > leeward.rainfall * 1.5, "A mountain ridge must produce wet windward slopes and a drier leeward side.")
	_check(climate.cell_info(Vector2(0.5, 0.5)).temperature < climate.cell_info(Vector2(0.25, 0.5)).temperature - 10, "High terrain must be colder than nearby lowland.")
	options.wind_rotation -= 180.0
	climate.generate(ridge, options)
	_check(climate.cell_info(Vector2(0.54, 0.5)).rainfall > climate.cell_info(Vector2(0.38, 0.5)).rainfall * 1.5, "Reversing the wind must reverse the ridge's wet and dry sides.")
	options.rainfall_scale = 0.0
	climate.generate(ridge, options)
	_check(climate.rainfall.count(0.0) == climate.rainfall.size(), "Zero rainfall must produce a dry map.")
	var invalid: Dictionary = options.duplicate()
	invalid.latitude_center = 89
	_check(not Climate.validate(invalid).is_empty(), "A latitude extent crossing a pole must be rejected.")
	invalid = options.duplicate()
	invalid.temperature_bias = NAN
	_check(not Climate.validate(invalid).is_empty(), "Nonfinite climate inputs must be rejected.")
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	terrain.map_size = Vector2(256, 256)
	terrain.regenerate()
	var panel = world.get_node("Interface/Editor/ClimatePanel")
	var mesh_id: int = terrain.detail.chunks[0].meshes[0].get_instance_id()
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var geography = terrain.geography
	var warmth_text: LineEdit = panel.controls.temperature_bias.get_line_edit()
	warmth_text.grab_focus()
	warmth_text.edit()
	await process_frame
	warmth_text.text = "7"
	warmth_text.text_changed.emit("7")
	panel.controls.latitude_span.value = 40
	await process_frame
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_LEFT
	drag.pressed = true
	drag.position = Vector2(62, 30)
	panel.gizmo._gui_input(drag)
	_check(panel.gizmo.latitude_center > 20, "Dragging the globe must change the map's latitude.")
	drag.position = Vector2(195, 22)
	panel.gizmo._gui_input(drag)
	_check(is_equal_approx(panel.gizmo.wind_rotation, -90.0), "Dragging the wind dial must change the wind offset.")
	await panel.apply_settings()
	_check(terrain.climate_settings.temperature_bias == 7 and terrain.climate_settings.latitude_span == 40 and terrain.climate_settings.latitude_center > 20, "Apply climate must commit typed warmth and use the real gizmo choices.")
	_check(terrain.height_samples == heights and terrain.geography == geography and terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh_id, "Climate edits must preserve heights, geographic identity and prebuilt LOD meshes.")
	var editor = world.get_node("Interface/Editor")
	editor._selected_cell = 0
	var original_options: Dictionary = terrain.climate_settings.duplicate()
	var dry_options: Dictionary = original_options.duplicate()
	dry_options.rainfall_scale = 0
	var wet_options: Dictionary = original_options.duplicate()
	wet_options.rainfall_scale = 3
	terrain.apply_climate(dry_options)
	_check(editor._cell_label.text.contains("Rainfall: 0 mm/yr") and editor._cell_label.text.contains("Biome:"), "Applying climate must refresh the selected cell without requiring another click.")
	var dry_biomes: PackedByteArray = terrain.biomes.ids.duplicate()
	var dry_colors: PackedByteArray = terrain._climate_texture.get_image().get_data()
	var palette_id: int = terrain._biome_texture.get_instance_id()
	terrain.apply_climate(wet_options)
	_check(terrain.biomes.ids != dry_biomes and terrain._climate_texture.get_image().get_data() != dry_colors, "Rainfall changes must alter biome IDs and the climate samples driving normal terrain colours.")
	_check(terrain._biome_texture.get_instance_id() == palette_id, "Climate edits must reuse the shared biome palette instead of rebuilding a blurred cover texture.")
	_check(terrain.height_samples == heights and terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh_id, "Visible biome changes must preserve the original terrain geometry.")
	_check(terrain._land_material.get_shader_parameter("biomes_enabled") and terrain.detail._material.get_shader_parameter("biomes_enabled"), "Normal terrain and every LOD must use climate-driven cover.")
	terrain.apply_climate(original_options)
	var saved_biomes: PackedByteArray = terrain.biomes.ids.duplicate()
	var saved: Dictionary = Document.capture(terrain)
	_check(saved.version == Document.VERSION and Document.validate(saved).is_empty(), "Climate parameters must form a valid current-version map document.")
	var path := "res://.godot/climate-roundtrip.terrain.json"
	_check(Document.save_file(path, terrain).is_empty(), "Climate maps must save through the real file pipeline.")
	var saved_field: PackedFloat32Array = terrain.climate.field.duplicate()
	terrain.apply_climate(Climate.DEFAULTS)
	var loaded: Dictionary = Document.load_file(path)
	_check(loaded.ok and Document.apply(terrain, loaded.document).is_empty() and terrain.climate.field == saved_field and terrain.biomes.ids == saved_biomes, "Saved climate settings must regenerate exactly after JSON reload.")
	var bad: Dictionary = saved.duplicate(true)
	bad.climate.settings.rainfall_scale = -1
	_check(not Document.apply(terrain, bad).is_empty() and terrain.climate.field == saved_field, "Invalid climate saves must be rejected before changing the current map.")
	var old: Dictionary = saved.duplicate(true)
	old.version = 5
	old.erase("climate")
	_check(Document.apply(terrain, old).is_empty() and terrain.climate_settings == Climate.DEFAULTS and terrain.height_samples == heights, "Older maps must gain default climate without changing saved terrain.")
	for mode in range(4):
		panel.overlay.select(mode)
		panel.overlay.item_selected.emit(mode)
		_check(terrain._land_material.get_shader_parameter("climate_mode") == mode and terrain.detail._material.get_shader_parameter("climate_mode") == mode, "Overlay selection must reach both base and LOD materials.")
	_check(terrain.cell_info(0).has("temperature") and terrain.cell_info(0).has("rainfall") and terrain.cell_info(0).has("biome"), "Cell inspection must expose climate fields.")
	if DisplayServer.get_name() != "headless":
		# A useful visible case, after the save/compatibility checks.
		terrain.terrain_template = "Continents"
		terrain.island_enabled = false
		terrain.regenerate()
		world.get_node("Interface/Editor")._sync_from_terrain()
		world.get_node("CameraRig")._reset_view()
		await process_frame
		for mode in [0, 1, 2, 3]:
			panel.overlay.select(mode)
			panel.overlay.item_selected.emit(mode)
			if mode == 1:
				var camera = world.get_node("CameraRig/Camera3D")
				var site: Vector2 = terrain.graph.points[terrain.graph.count / 2] / terrain.map_size
				var position: Vector2 = (site - Vector2(0.5, 0.5)) * terrain.map_size
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				click.position = camera.unproject_position(Vector3(position.x, terrain.surface_height(site), position.y))
				world.get_node("Interface/Editor")._unhandled_input(click)
				_check(world.get_node("Interface/Editor")._cell_label.text.contains("Temperature:"), "The real inspector must show climate when clicking the map.")
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/climate-%d.png" % mode)
		# Same terrain and camera: climate alone changes the normal terrain view.
		panel.overlay.select(0)
		panel.overlay.item_selected.emit(0)
		for scenario in ["dry", "wet"]:
			var scenario_options: Dictionary = Climate.DEFAULTS.duplicate()
			scenario_options.latitude_center = 20
			scenario_options.latitude_span = 20
			scenario_options.rainfall_scale = 0.0 if scenario == "dry" else 3.0
			terrain.apply_climate(scenario_options)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/biomes-%s.png" % scenario)
		var rig = world.get_node("CameraRig")
		var target_cell: int = 0
		var target_score: float = INF
		for cell in range(terrain.graph.count):
			var info: Dictionary = terrain.cell_info(cell)
			if info.height > 30 and info.height < 65:
				var score: float = absf(info.rainfall - 1500.0)
				if score < target_score:
					target_cell = cell
					target_score = score
		var target: Vector2 = terrain.graph.points[target_cell] - terrain.map_size * 0.5
		rig.position.x = target.x
		rig.position.z = target.y
		rig._zoom = 8.0
		rig._apply_zoom()
		terrain.detail._process(1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/biomes-close.png")
	DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	world.queue_free()
	await process_frame
	print("Terrain climate checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
