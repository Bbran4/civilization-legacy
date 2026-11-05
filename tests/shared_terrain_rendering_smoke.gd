extends SceneTree
const Document = preload("res://scripts/storage/terrain_document.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var editor = world.get_node("Interface/Editor")
	var terrain = world.get_node("Terrain")
	await terrain.wait_for_presentation()
	var original: PackedFloat32Array = terrain.height_samples.duplicate()
	var export_bytes: PackedByteArray = terrain.heightmap_image().get_data()
	var dirty_before: bool = editor.dirty
	check(terrain.shaded_relief and terrain.map_renderer.material.get_shader_parameter("shaded_relief"), "Editor defaults to the shared shaded-relief presentation.")
	check(terrain.map_renderer.material.shader == Renderer.SHADER, "Editor uses the shared runtime shader.")
	var editor_image: Image
	var sample_rect: Rect2i
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		editor_image = root.get_texture().get_image()
		var camera: Camera3D = world.get_node("CameraRig/Camera3D")
		var extent: Vector2 = terrain.display_size()
		var a := Vector2i(camera.unproject_position(Vector3(-extent.x * 0.5, 0, -extent.y * 0.5)))
		var b := Vector2i(camera.unproject_position(Vector3(extent.x * 0.5, 0, extent.y * 0.5)))
		sample_rect = Rect2i(a + Vector2i(4, 4), b - a - Vector2i(8, 8))
	editor.find_child("PlayMap", true, false).pressed.emit()
	await process_frame
	var game = editor._gameplay_map
	check(game != null and not world.visible and not world.get_node("Interface").visible and world.process_mode == Node.PROCESS_MODE_DISABLED, "Play map replaces the authoring presentation and suspends its input.")
	if game == null:
		quit(1)
		return
	var runtime = game.get_node("Terrain")
	await runtime.wait_for_presentation()
	check(runtime.height_samples == original and runtime.map_seed == terrain.map_seed and runtime.sample_size() == terrain.sample_size(), "Gameplay receives exact authored samples, seed and resolution.")
	check(runtime.map_renderer.material.shader == terrain.map_renderer.material.shader and runtime.shaded_relief, "Both surfaces share the same shader with relief enabled.")
	check(runtime.map_renderer.material.get_shader_parameter("height_field").get_image().get_data() == terrain.map_renderer.material.get_shader_parameter("height_field").get_image().get_data(), "The renderer receives identical float height textures in gameplay and editor.")
	check(runtime.heightmap_only and runtime.texture_settings == terrain.texture_settings and runtime.tree_settings == terrain.tree_settings, "Gameplay retains the focused pipeline and authored appearance settings.")
	check(not game.has_node("Interface/Editor") and not game.has_node("LayerStack"), "Gameplay scene contains no authoring interface.")
	check(runtime.startup_document.is_empty() and runtime.heightmap_image().get_data() == export_bytes, "Startup consumes the document once without changing exports.")
	if editor_image != null:
		# Functional parity at identical framing; this is not a zoom/performance review.
		var rig = game.get_node("CameraRig")
		var editor_rig = world.get_node("CameraRig")
		rig.sidebar_width = editor_rig.sidebar_width
		rig.panel_balance = editor_rig.panel_balance
		rig._reset_view()
		await process_frame
		await RenderingServer.frame_post_draw
		var runtime_image := root.get_texture().get_image()
		var error := 0.0
		var count := 0
		for y in range(sample_rect.position.y, sample_rect.end.y, 5):
			for x in range(sample_rect.position.x, sample_rect.end.x, 5):
				error += absf(editor_image.get_pixel(x, y).r - runtime_image.get_pixel(x, y).r)
				count += 1
		check(count > 0 and error / maxf(1, count) < 0.002, "GPU editor/gameplay relief output matches at identical framing.")
	game.find_child("ReturnToEditor", true, false).pressed.emit()
	await process_frame
	check(editor._gameplay_map == null and world.visible and world.get_node("Interface").visible and world.process_mode != Node.PROCESS_MODE_DISABLED, "Return restores the editor interface, processing and active camera.")
	check(terrain.height_samples == original and editor.dirty == dirty_before and world.get_node("CameraRig/Camera3D").current, "A play session preserves authored data, dirty state and camera ownership.")
	# Raw data inspection is an editor option; it must never leak into the player's view.
	editor.find_child("RawHeightView", true, false).button_pressed = true
	check(not terrain.shaded_relief and terrain.heightmap_image().get_data() == export_bytes, "Raw editor inspection leaves exports unchanged.")
	editor.play_map()
	await process_frame
	game = editor._gameplay_map
	check(game.get_node("Terrain").shaded_relief and game.get_node("Terrain").height_samples == original, "Gameplay still uses shaded relief when the editor is inspecting raw heights.")
	# Native close returns to the editor before asking about its unsaved document.
	editor.mark_dirty()
	root.close_requested.emit()
	check(editor._gameplay_map == null and world.visible and editor._unsaved_dialog.visible, "Window close retains the existing unsaved-change safeguard.")
	editor._unsaved_dialog.hide()
	editor._unsaved_dialog.canceled.emit()
	await process_frame
	var document := Document.capture(terrain)
	world.queue_free()
	await process_frame
	# Verify the runtime scene also works with no editor node anywhere in the tree.
	var standalone := (load("res://scenes/gameplay_map.tscn") as PackedScene).instantiate()
	standalone.get_node("Terrain").startup_document = document
	root.add_child(standalone)
	await process_frame
	check(standalone.get_node("Terrain").height_samples == original and standalone.get_node("Terrain").shaded_relief, "Standalone gameplay loads and shades saved data without any editor dependency.")
	standalone.queue_free()
	await process_frame
	print("Shared terrain rendering: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
