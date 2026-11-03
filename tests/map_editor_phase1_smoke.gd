extends SceneTree
const Manifest = preload("res://scripts/storage/world_manifest.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var layers := Manifest.default_layers()
	check(layers.size() == 5 and layers[1].dependencies == ["heightmap", "climate"], "Layer contract exposes explicit dependencies.")
	var data := Manifest.capture(layers, "map.terrain.json", "heightmap")
	check(Manifest.validate(data).is_empty(), "Default manifest validates.")
	var bad := data.duplicate(true)
	bad.layers[1].id = "heightmap"
	check(not Manifest.validate(bad).is_empty(), "Duplicate layers are rejected.")
	bad = data.duplicate(true)
	bad.version = 999
	check(not Manifest.validate(bad).is_empty(), "Future versions are rejected.")
	bad = data.duplicate(true)
	bad.layers[0].locked = "false"
	check(not Manifest.validate(bad).is_empty(), "Layer flags require boolean types.")
	check(not Manifest.save_file("user://wrong.terrain.json", data).is_empty(), "Manifest writes cannot target terrain filenames.")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var editor = world.get_node("Interface/Editor")
	var terrain = world.get_node("Terrain")
	check(editor.has_node("Toolbar") and editor.has_node("LayerStack") and editor.has_node("PropertiesPanel") and editor.has_node("MapViewport"), "Shell exposes all four workspace regions.")
	for layer in editor.layers:
		editor._select_layer(layer.id)
		for key in editor._contexts:
			check(editor._contexts[key].visible == (key == layer.id), "Only selected layer properties are shown.")
	editor._select_layer("heightmap")
	var before: PackedFloat32Array = terrain.height_samples.duplicate()
	editor._layer_buttons.heightmap[1].button_pressed = true
	editor.apply_settings()
	check(before == terrain.height_samples and not editor.can_edit("heightmap"), "Heightmap lock blocks generation.")
	editor._layer_buttons.heightmap[1].button_pressed = false
	editor._layer_buttons.trees[1].button_pressed = true
	editor.apply_settings()
	check(before == terrain.height_samples, "Downstream lock protects data from terrain regeneration.")
	editor._tree_population.value = 0
	await editor._apply_trees()
	check(terrain.tree_population != 0, "Locked trees reject direct edits.")
	editor._layer_buttons.trees[1].button_pressed = false
	editor._select_layer("ground")
	editor._brush.enabled.button_pressed = true
	editor._layer_buttons.ground[1].button_pressed = true
	check(not editor._brush.enabled.button_pressed, "Lock cancels active brush.")
	editor._brush.clear()
	editor._layer_buttons.ground[1].button_pressed = false
	for id in ["trees", "rivers", "ground", "heightmap"]:
		editor._layer_buttons[id][0].button_pressed = false
	check(not terrain.visible and not terrain.vegetation_view.editor_visible and not terrain.hydrology_view.editor_visible and not terrain.paint_layer.editor_visible, "Visibility controls route to display systems.")
	terrain.vegetation_view.set_view(0, false)
	terrain.hydrology_view.set_view(0, false)
	check(not terrain.vegetation_view.visible and not terrain.hydrology_view.visible, "Camera and view changes preserve hidden state.")
	check(before == terrain.height_samples, "Layer operations never mutate height samples.")
	var terrain_path := "user://phase1.terrain.json"
	check(Document.save_file(terrain_path, terrain).is_empty(), "Legacy terrain save remains usable.")
	var saved := FileAccess.get_file_as_bytes(terrain_path)
	editor._terrain_path = terrain_path
	editor._dialog_action = "save_world"
	editor._file_selected(ProjectSettings.globalize_path("user://ui.world.json"))
	var ui_world := Manifest.load_file("user://ui.world.json")
	check(ui_world.error.is_empty() and ui_world.document.terrain == "phase1.terrain.json", "Toolbar saves a relative reference alongside terrain.")
	data = Manifest.capture(editor.layers, "phase1.terrain.json", "ground")
	var path := "user://phase1.world.json"
	check(Manifest.save_file(path, data).is_empty(), "World manifest saves independently.")
	check(Manifest.save_file(path, data).is_empty() and FileAccess.file_exists(path + ".bak"), "World overwrites retain backups.")
	editor._layer_buttons.heightmap[0].button_pressed = true
	check(editor.load_world(path).is_empty(), "World loads a relative terrain reference.")
	check(editor.selected_layer == "ground" and not terrain.visible and before == terrain.height_samples, "World restores selection, visibility and exact terrain.")
	check(FileAccess.get_file_as_bytes(terrain_path) == saved, "World save/load never rewrites referenced terrain.")
	bad = data.duplicate(true)
	bad.terrain = "missing.terrain.json"
	check(Manifest.save_file("user://missing.world.json", bad).is_empty(), "Missing reference fixture saves.")
	check(not editor.load_world("user://missing.world.json").is_empty() and before == terrain.height_samples, "Missing terrain rejects world without changing current map.")
	if DisplayServer.get_name() != "headless":
		editor._layer_buttons.heightmap[0].button_pressed = true
		editor._select_layer("heightmap")
		await process_frame
		await RenderingServer.frame_post_draw
		editor._status.text = "Phase 1 workspace · Existing terrain retained"
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/editor-phase1.png")
	world.queue_free()
	await process_frame
	print("Map Editor Phase 1: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
