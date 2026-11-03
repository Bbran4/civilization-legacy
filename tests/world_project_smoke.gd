extends SceneTree
const Manifest = preload("res://scripts/storage/world_manifest.gd")
const Project = preload("res://scripts/storage/world_project.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
const Graph = preload("res://scripts/domain/map_layer_graph.gd")
var failures := 0
var continued := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _continue() -> void:
	continued += 1

func _dismiss(dialog: ConfirmationDialog, discard: bool) -> void:
	dialog.hide()
	if discard:
		dialog.confirmed.emit()
	else:
		dialog.canceled.emit()

func _run() -> void:
	var layers := Manifest.default_layers()
	check(Graph.affected(layers, "heightmap").size() == 5, "Height changes reach every dependent layer.")
	check(Graph.affected(layers, "climate") == ["climate", "rivers", "trees"], "Climate affects water and trees, not authored ground.")
	check(Graph.affected(layers, "ground") == ["ground"], "Ground edits do not invalidate terrain.")
	check(Graph.affected(layers, "unknown").is_empty() and not Graph.lock_reason(layers, "unknown").is_empty(), "Unknown layer operations are rejected.")
	layers[0].dependencies.append("trees")
	check(Graph.affected(layers, "heightmap").size() == 5, "Traversal terminates even when extensions introduce cycles.")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var editor = world.get_node("Interface/Editor")
	var terrain = world.get_node("Terrain")
	check(editor.dirty and editor._world_status.text.contains("Unsaved"), "New world is visibly unsaved.")
	var directory := "user://world-project-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var legacy := directory.path_join("legacy.terrain.json")
	check(Document.save_file(legacy, terrain).is_empty(), "Legacy fixture saves.")
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy)
	var path := directory.path_join("current.world.json")
	check(editor.save_world(path).is_empty() and not editor.dirty, "Save world works without a separate terrain save step.")
	var first: Dictionary = Manifest.load_file(path).document
	var first_path: String = directory.path_join(first.terrain)
	check(first.terrain != "legacy.terrain.json" and not first.terrain.is_absolute_path(), "World references a new portable snapshot.")
	var first_bytes := FileAccess.get_file_as_bytes(first_path)
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	check(FileAccess.get_file_as_bytes(legacy) == legacy_bytes, "Save world never overwrites the imported legacy source.")
	editor._layer_buttons.trees[0].button_pressed = false
	check(editor.dirty, "Visibility changes dirty workspace state.")
	check(editor.save_world(path).is_empty(), "A changed workspace saves.")
	var second: Dictionary = Manifest.load_file(path).document
	check(first.terrain != second.terrain and FileAccess.get_file_as_bytes(first_path) == first_bytes, "Repeat save preserves the previous immutable payload.")
	var backup: Dictionary = Manifest.load_file(path + ".bak").document
	check(backup.terrain == first.terrain and Document.load_file(first_path).ok, "Backup manifest still references its original valid payload.")
	# Fail after terrain writing by making the manifest target an existing directory.
	var bad_path := directory.path_join("blocked.world.json")
	DirAccess.make_dir_recursive_absolute(bad_path)
	var previous_files := DirAccess.get_files_at(directory)
	var prior_manifest := FileAccess.get_file_as_bytes(path)
	editor.mark_dirty()
	check(not editor.save_world(bad_path).is_empty() and editor.dirty, "Failed save never clears dirty state.")
	check(DirAccess.get_files_at(directory) == previous_files and FileAccess.get_file_as_bytes(path) == prior_manifest, "Late save failure cleans its new snapshot and preserves previous files.")
	check(not editor.save_world(directory.path_join("wrong.terrain.json")).is_empty(), "Wrong save suffix is rejected.")
	# Save As creates a self-contained terrain reference in the destination folder.
	var moved := directory.path_join("moved")
	DirAccess.make_dir_recursive_absolute(moved)
	var moved_path := moved.path_join("copy.world.json")
	check(editor.save_world(moved_path).is_empty(), "Save As copies the visible world to another directory.")
	var moved_data: Dictionary = Manifest.load_file(moved_path).document
	check(Document.load_file(moved.path_join(moved_data.terrain)).ok, "Save As reference resolves beside its manifest.")
	# Dependency-aware regeneration must allow unaffected locks and report affected ones.
	editor._select_layer("climate")
	await process_frame
	editor._layer_buttons.heightmap[1].button_pressed = true
	editor._layer_buttons.ground[1].button_pressed = true
	check(editor.regeneration_error("climate").is_empty(), "Ground and height locks allow climate changes.")
	var paint_before: Dictionary = terrain.paint_layer.snapshot()
	editor._climate_panel.controls.temperature_bias.value = 5
	await process_frame
	await editor._climate_panel.apply_settings()
	check(terrain.climate_settings.temperature_bias == 5 and terrain.height_samples == heights and terrain.paint_layer.snapshot() == paint_before, "Climate applies without changing locked heights or ground.")
	editor._layer_buttons.rivers[1].button_pressed = true
	check(editor.regeneration_error("climate").contains("Rivers / lakes"), "Affected lock explains the blocking layer.")
	editor._climate_panel.controls.temperature_bias.value = 8
	await editor._climate_panel.apply_settings()
	check(terrain.climate_settings.temperature_bias == 5, "Locked rivers protect against climate-driven regeneration.")
	for layer in editor.layers:
		editor._layer_buttons[layer.id][1].button_pressed = false
	# Actual paint, undo, palette application and tree signals participate in dirty tracking.
	editor._select_layer("ground")
	check(editor.save_world(moved_path).is_empty(), "World saves before edit tracking checks.")
	terrain.paint_layer.begin_stroke()
	editor._brush._paint(terrain.map_size * 0.5)
	check(editor.dirty and terrain.paint_layer.image != null, "Ground painting marks data dirty.")
	check(editor.save_world(moved_path).is_empty(), "Painted world saves.")
	var painted := Document.load_file(editor._terrain_path)
	check(painted.ok and painted.document.ground_paint.png == terrain.paint_layer.snapshot().png and painted.document.climate.settings.temperature_bias == 5, "World Save All captures the current paint and climate, not a previous terrain file.")
	editor._brush.undo()
	check(editor.dirty, "Undo marks data dirty.")
	editor.save_world(moved_path)
	editor._open_ground_palette()
	await editor._material_panel._apply()
	check(editor.dirty, "Applied palette changes mark data dirty.")
	editor._material_panel.hide()
	editor.save_world(moved_path)
	terrain.vegetation_changed.emit()
	check(editor.dirty, "Tree changes mark data dirty.")
	# Unsaved action cancellation, discard, successful save and failed save.
	editor.request_action(_continue)
	check(editor._unsaved_dialog.visible and continued == 0, "Dirty document replacement waits for a decision.")
	_dismiss(editor._unsaved_dialog, false)
	check(continued == 0 and editor.dirty and not editor._pending_action.is_valid(), "Cancel preserves current world and clears the pending action.")
	editor.request_action(_continue)
	_dismiss(editor._unsaved_dialog, true)
	check(continued == 1 and editor.dirty, "Discard continues once; only a successful replacement clears state.")
	editor.request_action(_continue)
	editor._unsaved_dialog.custom_action.emit("save")
	check(continued == 2 and not editor.dirty, "Save and continue resumes only after successful world publication.")
	editor.request_action(_continue)
	check(continued == 3, "Clean documents continue without prompting.")
	editor.mark_dirty()
	editor._world_path = bad_path
	editor.request_action(_continue)
	editor._unsaved_dialog.custom_action.emit("save")
	check(continued == 3 and editor.dirty and not editor._pending_action.is_valid(), "Failed Save and continue never runs or retains the pending action.")
	editor.mark_dirty()
	root.close_requested.emit()
	check(editor._unsaved_dialog.visible and not auto_accept_quit, "Native window close is guarded while the world is dirty.")
	_dismiss(editor._unsaved_dialog, false)
	# A save cancelled before choosing a location also abandons the pending replacement.
	editor._world_path = ""
	editor.request_action(_continue)
	editor._unsaved_dialog.custom_action.emit("save")
	check(editor._dialog.visible and continued == 3, "New worlds request a location before continuing.")
	editor._dialog.hide()
	editor._dialog.canceled.emit()
	check(not editor._pending_action.is_valid() and editor.dirty, "Cancelling the save chooser retains edits and cancels replacement.")
	check(editor.load_world(moved_path).is_empty() and not editor.dirty, "Opening a saved world resets dirty state after all signals.")
	var loaded_path: String = editor._world_path
	check(not editor.load_world(directory.path_join("missing.world.json")).is_empty() and editor._world_path == loaded_path and not editor.dirty, "Failed open retains current world identity and clean state.")
	if DisplayServer.get_name() != "headless":
		editor._select_layer("climate")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/editor-world-workflow.png")
	world.queue_free()
	await process_frame
	print("World project workflow: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
