extends SceneTree
## Exercises the actual native addon: generation, editing, and persisted reload.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var trial = load("res://scenes/terrain3d_trial.tscn").instantiate()
	trial.width = 256
	trial.length = 256
	root.add_child(trial)
	await process_frame
	trial.generate()
	var terrain: Terrain3D = trial.get_node("Terrain3D")
	check(terrain.data.get_region_count() == 1, "256-square generation allocates one region")
	var appearance_height: float = terrain.data.get_height(Vector3(100, 0, 100))
	var appearance_control: PackedByteArray = terrain.data.get_regions_active()[0].get_control_map().get_data()
	trial.refresh_appearance()
	check(terrain.data.get_height(Vector3(100, 0, 100)) == appearance_height and terrain.data.get_regions_active()[0].get_control_map().get_data() == appearance_control, "Refreshing appearance preserves sculpted heights and material painting")
	var first: Image = terrain.data.get_regions_active()[0].get_height_map().duplicate()
	trial.generate()
	check(first.get_data() == terrain.data.get_regions_active()[0].get_height_map().get_data(), "Identical seed reproduces exact heights")
	trial.world_seed = "different"
	trial.generate()
	check(first.get_data() != terrain.data.get_regions_active()[0].get_height_map().get_data(), "Different seed changes terrain")
	for preset in ["Volcano", "Old World", "Mediterranean"]:
		trial.template = preset
		trial.generate()
		check(is_finite(terrain.data.get_height(Vector3(128, 0, 128))), preset + " imports finite native terrain")
	trial.template = "World heightmap"
	trial.width = 512
	trial.generate()
	check(trial.length == 256 and terrain.data.get_region_count() == 2, "Bundled world imports with its 2:1 aspect ratio")
	check(trial.applied_settings.heightmap_file == "res://data/heightmaps/world.png", "Snapshot records the actual imported source")
	check(trial.applied_settings.heightmap_source_size == [600, 293], "Imported metadata distinguishes source detail from terrain resolution")
	# Float EXR fixture checks orientation, precision and mapping into native heights.
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	var source := Image.create(8, 4, false, Image.FORMAT_RF)
	for y in range(4):
		for x in range(8):
			source.set_pixel(x, y, Color(0.123456 + x * 0.08 + y * 0.025, 0, 0))
	var image_path := "res://.test-runtime/terrain3d-height-source.exr"
	check(source.save_exr(image_path, false) == OK, "Float height source saves")
	trial.select_heightmap_file(ProjectSettings.globalize_path(image_path))
	check(trial.applied_settings.template == "World heightmap", "Selecting an image leaves the current world unchanged")
	if not Engine.is_editor_hint():
		check(trial._preset_control.get_item_text(trial._preset_control.selected) == "Imported heightmap", "File selection updates the visible source selector")
	trial.width = 256
	trial.length = 256
	trial.match_heightmap_aspect = false
	trial.imported_relief = 1.0
	trial.generate()
	source.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	for location in [Vector2i(32, 48), Vector2i(192, 48), Vector2i(32, 208)]:
		var expected: float = (source.get_pixelv(location).r - trial.sea_level) * 1.28
		check(absf(terrain.data.get_height(Vector3(location.x, 0, location.y)) - expected) < 0.0001, "Imported samples retain precision, orientation and height/sea scaling")
	trial.invert_heightmap = true
	trial.generate()
	check(absf(terrain.data.get_height(Vector3(32, 0, 48)) - (1.0 - source.get_pixel(32, 48).r - trial.sea_level) * 1.28) < 0.0001, "Height inversion is explicit")
	var imported: PackedByteArray = terrain.data.get_regions_active()[0].get_height_map().get_data()
	trial.mountain_detail = 1.0
	trial.height_range = 500.0
	trial.generate()
	check(imported == terrain.data.get_regions_active()[0].get_height_map().get_data(), "Procedural height range and mountain detail cannot alter an imported map")
	check(not trial.applied_settings.has("mountain_detail") and not trial.applied_settings.has("height_range"), "Imported metadata records only applied controls")
	var before_relief: float = terrain.data.get_height(Vector3(32, 0, 48))
	trial.imported_relief = 0.5
	trial.generate()
	check(absf(terrain.data.get_height(Vector3(32, 0, 48)) - before_relief * 0.5) < 0.0001, "Imported relief scales around the fixed sea datum")
	trial.imported_relief = 1.0
	trial.generate()
	if not Engine.is_editor_hint():
		check(not trial._dimension_controls.height_range.get_parent().visible and trial._dimension_controls.imported_relief.get_parent().visible, "Imported UI exposes relief instead of procedural height range")
	var retained: float = terrain.data.get_height(Vector3(32, 0, 48))
	var applied: Dictionary = trial.applied_settings.duplicate()
	trial.heightmap_file = "res://.test-runtime/missing-heightmap.png"
	trial.generate()
	check(terrain.data.get_height(Vector3(32, 0, 48)) == retained and trial.applied_settings == applied, "Missing input preserves authored terrain and source metadata")
	trial.heightmap_file = ProjectSettings.globalize_path(image_path)
	var point := Vector3(128, 0, 128)
	terrain.data.set_height(point, 27.5)
	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT)
	check(is_equal_approx(terrain.data.get_height(point), 27.5), "Native height editing works")
	if Engine.is_editor_hint():
		trial.save_snapshot()
		var saved: String = trial.last_snapshot
		check(not saved.is_empty(), "Snapshot verified")
		var restored := Terrain3D.new()
		restored.free_editor_textures = false
		root.add_child(restored)
		restored.data_directory = saved
		await process_frame
		check(is_equal_approx(restored.data.get_height(point), 27.5), "Edited heights survive native save/reload")
		DirAccess.make_dir_recursive_absolute("res://.test-runtime")
		var packed := PackedScene.new()
		check(packed.pack(trial) == OK, "Authored scene packs")
		check(ResourceSaver.save(packed, "res://.test-runtime/terrain3d-saved.tscn") == OK, "Authored scene saves")
		var reopened = ResourceLoader.load("res://.test-runtime/terrain3d-saved.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		root.add_child(reopened)
		await process_frame
		check(is_equal_approx(reopened.get_node("Terrain3D").data.get_height(point), 27.5), "Scene reload retains sculpted terrain")
		check(reopened.get_node("Terrain3D").assets.get_texture_count() == 2, "Scene reload retains material assets")
		reopened.queue_free()
		trial.generate()
		check(terrain.data_directory.is_empty(), "Regeneration detaches saved snapshot")
		check(is_equal_approx(restored.data.get_height(point), 27.5), "Regeneration preserves previous snapshot")
		restored.queue_free()
	else:
		trial.save_snapshot()
		check(trial.last_snapshot.is_empty(), "Unsafe runtime region saving is unavailable")
	if "--capture" in OS.get_cmdline_user_args() or "--capture-world" in OS.get_cmdline_user_args():
		var capture_world := "--capture-world" in OS.get_cmdline_user_args()
		trial.template = "World heightmap" if capture_world else "High Island"
		trial.invert_heightmap = false
		trial.world_seed = "1324865"
		trial.width = 2048 if capture_world else 1024
		trial.length = 1024
		trial.match_heightmap_aspect = true
		trial.generate()
		DirAccess.make_dir_recursive_absolute("res://.test-runtime")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-runtime/terrain3d-world-preview.png" if capture_world else "res://.test-runtime/terrain3d-preview.png")
	trial.queue_free()
	await process_frame
	print("Terrain3D trial smoke: %d failures" % failures)
	quit(1 if failures else 0)
