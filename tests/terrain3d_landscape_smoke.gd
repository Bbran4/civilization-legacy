extends SceneTree
const Hydrology = preload("res://scripts/domain/terrain3d_hydrology.gd")
const Climate = preload("res://scripts/domain/landscape_climate.gd")
const Weathering = preload("res://scripts/domain/mountain_weathering.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var size := Vector2i(129, 97)
	var base := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	for y in range(size.y):
		for x in range(size.x):
			var uv := Vector2(x, y) / Vector2(size - Vector2i.ONE)
			var basin := exp(-pow((uv.x - 0.5) / 0.12, 2) - pow((uv.y - 0.45) / 0.12, 2)) * 0.28
			base.set_pixel(x, y, Color(0.85 - uv.y * 0.8 + sin(uv.x * 18) * 0.015 - basin, 0, 0))
	var original := base.get_data()
	var climate := Climate.new()
	climate.generate(base, 0.2, "rainfall-test", 1.5, 0, 225)
	var repeated := Climate.new()
	repeated.generate(base, 0.2, "rainfall-test", 1.5, 0, 225)
	check(climate.runoff.get_data() == repeated.runoff.get_data(), "Climate runoff is reproducible")
	var landscape := Hydrology.new()
	var error := landscape.build(base, 0.2, climate.runoff, 2, 2, 0.006)
	check(error.is_empty(), "Synthetic watershed builds: " + error)
	if not error.is_empty():
		quit(1)
		return
	check(landscape.water.river_reaches > 0, "Rainfall generates river reaches")
	check(landscape.water.lake_count > 0, "Enclosed basin generates a lake")
	var wet := 0
	for i in range(landscape.levels.size()):
		if landscape.levels[i] >= 0:
			wet += 1
			check(landscape.heights[i] < landscape.levels[i], "Actual ground is carved below each hydraulic water surface")
	check(wet > 0 and landscape.surface.modified_pixels > 0, "Water changes ground geometry")
	check(base.get_data() == original, "Authoring source remains immutable")
	check(landscape.water.validate_hydraulics().is_empty(), "Rivers descend and meet lake/confluence elevations")
	climate.generate(base, 0.2, "rainfall-test", 0, 0, 225)
	var dry := Hydrology.new()
	error = dry.build(base, 0.2, climate.runoff, 2, 2, 0.006)
	check(error.is_empty() and dry.water.river_reaches == 0 and dry.water.lake_count == 0, "Zero rainfall produces no inland water")
	check(dry.heights.to_byte_array() == original, "Dry regeneration restores the exact uncarved source")
	var values := original.to_float32_array()
	var relaxed := Weathering.apply(values, size, 0.2, 0.5)
	var mass_before := 0.0
	var mass_after := 0.0
	for i in range(values.size()):
		mass_before += values[i]
		mass_after += relaxed[i]
		if values[i] <= 0.22:
			check(relaxed[i] == values[i], "Weathering preserves coastal samples")
	check(absf(mass_before - mass_after) < 0.001, "Mountain weathering conserves material")
	var trial = load("res://scenes/terrain3d_trial.tscn").instantiate()
	trial.template = "High Island"
	trial.width = 512
	trial.length = 512
	trial.world_seed = "river-test"
	trial.height_range = 40
	trial.mountain_detail = 0.3
	trial.rainfall = 1.5
	root.add_child(trial)
	await process_frame
	trial.generate()
	var terrain: Terrain3D = trial.get_node("Terrain3D")
	var control: PackedByteArray = terrain.data.get_regions_active()[0].get_control_map().get_data()
	trial.carve_water()
	check(trial.water_summary.get("rivers", 0) > 0 and trial.water_summary.get("carved_samples", 0) > 0, "Native Terrain3D receives carved rivers")
	check(trial.has_node("InlandWater") and trial.get_node("InlandWater").mesh.get_surface_count() > 0, "Visible inland water mesh is generated")
	check(terrain.data.get_regions_active()[0].get_control_map().get_data() == control, "Hydrology preserves authored material painting")
	var carved: PackedByteArray = terrain.data.get_regions_active()[0].get_height_map().get_data()
	trial.carve_water()
	check(terrain.data.get_regions_active()[0].get_height_map().get_data() == carved, "Repeat carving uses the retained source, not an already-cut bed")
	if Engine.is_editor_hint():
		trial.save_snapshot()
		check(FileAccess.file_exists(trial.water_base_file), "Pre-carving source persists")
		var packed := PackedScene.new()
		check(packed.pack(trial) == OK, "Landscape scene packs")
		DirAccess.make_dir_recursive_absolute("res://.test-runtime")
		check(ResourceSaver.save(packed, "res://.test-runtime/landscape-saved.tscn") == OK, "Landscape scene saves")
		var restored = ResourceLoader.load("res://.test-runtime/landscape-saved.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		root.add_child(restored)
		await process_frame
		check(restored.has_node("InlandWater"), "Water geometry reloads with the scene")
		var saved_material: ShaderMaterial = restored.get_node("InlandWater").material_override
		check(saved_material.get_shader_parameter("coverage") != null, "Smoothed water coverage reloads with its material")
		restored.carve_water()
		check(restored.get_node("Terrain3D").data.get_regions_active()[0].get_height_map().get_data() == carved, "Reloaded landscape rebuilds from its saved pre-carving source")
		restored._water_base = null
		restored.water_base_file = "res://.test-runtime/missing-pre-water.exr"
		var retained_hash: String = restored._native_fingerprint()
		restored.carve_water()
		check(restored._native_fingerprint() == retained_hash, "Missing retained source cannot cause cumulative carving")
		restored.queue_free()
	if "--capture" in OS.get_cmdline_user_args():
		trial._focus = Vector3(256, 8, 256)
		trial._distance = 500
		trial._update_camera()
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.test-runtime")
		root.get_texture().get_image().save_png("res://.test-runtime/terrain3d-landscape.png")
		trial.inspect_river()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-runtime/terrain3d-river-closeup.png")
	trial.rainfall = 0
	trial.carve_water()
	check(trial.water_summary.get("rivers", -1) == 0 and trial.water_summary.get("lakes", -1) == 0, "Native dry-climate rebuild removes generated water")
	var edited_region = terrain.data.get_regions_active()[0]
	var edited_image: Image = edited_region.get_height_map()
	edited_image.set_pixel(4, 4, Color(1000, 0, 0))
	edited_region.set_height_map(edited_image)
	var edited_hash: String = trial._native_fingerprint()
	trial.carve_water()
	check(trial._native_fingerprint() == edited_hash, "Out-of-range sculpted elevations are preserved on rejection")
	trial.queue_free()
	await process_frame
	print("Terrain3D landscape smoke: %d failures" % failures)
	quit(1 if failures else 0)
