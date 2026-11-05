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
	if "--capture" in OS.get_cmdline_user_args():
		trial.template = "High Island"
		trial.world_seed = "1324865"
		trial.width = 1024
		trial.length = 1024
		trial.generate()
		DirAccess.make_dir_recursive_absolute("res://.test-runtime")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-runtime/terrain3d-preview.png")
	trial.queue_free()
	await process_frame
	print("Terrain3D trial smoke: %d failures" % failures)
	quit(1 if failures else 0)
