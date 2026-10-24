extends SceneTree

const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, reason: String) -> void:
	if not condition:
		_failures += 1
		push_error(reason)


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var world := scene.instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	# Exercise the same controls and handlers used while the game runs.
	var picker: OptionButton = editor._controls["terrain_template"]
	for i in range(picker.item_count):
		if picker.get_item_text(i) == "Mediterranean":
			picker.select(i)
			picker.item_selected.emit(i)
	_check(editor._controls.size() == 9, "The editor must expose the six map controls and three live zoom settings.")
	for control in editor._controls.values():
		_check(not control.tooltip_text.is_empty(), "Each generation input must have plain-language help.")
	editor._controls["map_size.x"].value = 256
	editor._controls["map_size.y"].value = 256
	editor._controls["map_seed"].text = "simple-map"
	editor._controls["island_enabled"].button_pressed = false
	editor._controls["elevation"].value = 12.0
	editor.apply_settings()
	_check(terrain.terrain_template == "Mediterranean", "Runtime preset control must select the requested recipe.")
	_check(terrain.resolution == 256 and terrain.height_samples.size() == 257 * 257 and terrain.auto_density and terrain.close_detail_enabled, "Generation must select bounded detail automatically from the map dimensions.")
	var original: PackedFloat32Array = terrain.height_samples.duplicate()
	terrain.height_contrast = 3.0
	terrain.island_enabled = true
	terrain.elevation = 80.0
	terrain.auto_density = false
	terrain.graph_points = 5000
	terrain.land_noise.seed = 9090
	editor.apply_settings()
	_check(original == terrain.height_samples, "Only the visible map inputs may determine newly generated terrain, regardless of previous hidden settings.")
	var original_cells: PackedByteArray = terrain.graph.heights.duplicate()
	editor._controls["elevation"].value = 24.0
	editor.apply_settings()
	_check(terrain.graph.heights == original_cells and terrain.height_samples != original and terrain.elevation == 24.0, "Elevation must change relief without changing coastal cell heights.")
	editor._controls["island_enabled"].button_pressed = true
	editor.apply_settings()
	_check(terrain.island_enabled and terrain.graph.heights != original_cells, "Island shaping must lower the map edges through the visible control.")
	var shaped: Dictionary = Document.capture(terrain)
	_check(Document.validate(shaped).is_empty() and shaped.settings.island_enabled and shaped.settings.elevation == 24.0, "Island and elevation choices must be stored in terrain saves.")
	editor._controls["island_enabled"].button_pressed = false
	editor._controls["elevation"].value = 12.0
	editor.apply_settings()
	_check(terrain.height_samples == original, "Disabling island shaping and restoring elevation must reproduce the original map.")
	var zoom_keys: Array[String] = ["min_zoom", "max_zoom", "closest_view_size"]
	var zoom_hints: Dictionary = {}
	for key in zoom_keys:
		var spin: SpinBox = editor._controls[key]
		_check(spin.get_line_edit().get_tooltip() == spin.tooltip_text and not zoom_hints.has(spin.tooltip_text), "Every zoom text field must receive its own distinct tooltip, including its internal LineEdit.")
		zoom_hints[spin.tooltip_text] = true
		_check(spin.update_on_text_changed, "Typed zoom settings must apply without waiting for Enter or losing focus.")
	var zoom_camera = world.get_node("CameraRig")
	var zoom_cache = terrain.geography
	editor._controls["min_zoom"].value = 0.5
	var max_text: LineEdit = editor._controls["max_zoom"].get_line_edit()
	max_text.grab_focus()
	max_text.edit()
	max_text.text = "6"
	max_text.text_changed.emit("6")
	await process_frame
	max_text.unedit()
	max_text.release_focus()
	_check(zoom_camera.max_zoom == 6.0, "Typing a maximum zoom must change the real camera immediately.")
	zoom_camera._zoom = 50.0
	zoom_camera._apply_zoom()
	_check(zoom_camera._zoom == 6.0 and terrain.geography == zoom_cache, "Live maximum zoom must clamp the camera without regenerating terrain.")
	zoom_camera._zoom = 0.1
	zoom_camera._apply_zoom()
	_check(zoom_camera._zoom == 0.5 and is_equal_approx(zoom_camera.rotation_degrees.x, -90.0), "Minimum zoom must preserve the flat overview when zooming out.")
	editor._controls["min_zoom"].value = 1.0
	editor._controls["max_zoom"].value = 8192.0
	editor.find_child("ClosestView", true, false).pressed.emit()
	var closest_before: float = zoom_camera._camera.size
	editor._controls["closest_view_size"].value = 4.0
	editor.find_child("ClosestView", true, false).pressed.emit()
	_check(is_equal_approx(zoom_camera._camera.size, 4.0) and is_equal_approx(closest_before, 8.0), "The third zoom setting must visibly double close-up magnification from an 8-unit to a 4-unit view.")
	_check(editor._zoom_status.text.contains("Closest view size limits"), "The effective range must explain when the closest-view setting overrides maximum zoom.")
	editor._controls["closest_view_size"].value = 8.0
	editor._controls["max_zoom"].value = 6.0
	_check(editor._zoom_status.text.contains("Maximum zoom limits"), "The effective range must explain when the maximum multiplier is the active limit.")
	editor._controls["min_zoom"].value = 0.5
	editor.find_child("FarthestView", true, false).pressed.emit()
	_check(zoom_camera._zoom == 0.5 and is_equal_approx(zoom_camera._camera.size, zoom_camera._fit_size * 2.0), "The farthest-view button must visibly show the configured outward limit.")
	editor._controls["min_zoom"].value = 1.0
	editor._controls["max_zoom"].value = 2048.0
	var preset_heights: Dictionary = {}
	var graph = Graph.new()
	graph.generate(Vector2(1024, 768), 1000, "42")
	for preset in Recipe.PRESETS:
		var heights: PackedByteArray = Recipe.new().generate(graph, preset, "42")
		_check(heights.size() == graph.count, preset + " must produce a height for each Voronoi cell.")
		_check(heights == Recipe.new().generate(graph, preset, "42"), preset + " must be deterministic.")
		_check(heights != Recipe.new().generate(graph, preset, "43"), preset + " must respond to its seed.")
		for height in heights:
			_check(height >= 0 and height <= 100, "Cell heights must remain within upstream bounds.")
		preset_heights[preset] = heights
	_check(preset_heights.Volcano != preset_heights.Mediterranean, "Different templates must yield different landforms.")
	var camera = world.get_node("CameraRig")
	camera._reset_view()
	_check(is_equal_approx(camera.rotation_degrees.x, -90.0) and is_equal_approx(camera.rotation_degrees.y, 0.0), "The full-map view must be exactly overhead and north-up.")
	_check(is_equal_approx(terrain.overview_blend, 1.0) and not world.get_node("Sun").shadow_enabled, "The full-map view must use flat map colours without 3D shadows.")
	_check(camera._pan_down().dot(Vector3.BACK) > 0.99, "Panning must remain usable in the exactly overhead view.")
	camera._zoom = 4.0
	camera._apply_zoom()
	_check(is_equal_approx(camera.rotation_degrees.x, -55.0) and world.get_node("Sun").shadow_enabled and is_zero_approx(terrain.overview_blend), "Zooming in must restore the angled, shaded terrain view.")
	var before: Vector3 = camera.rotation_degrees
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	drag.relative = Vector2(10.0, 10.0)
	camera._unhandled_input(drag)
	_check(camera.rotation_degrees.x < before.x, "Downward right-drag must use the reversed tilt direction.")
	_check(camera.rotation_degrees.y < before.y, "Horizontal orbit direction must remain unchanged.")
	var path: String = "res://.godot/roundtrip.terrain.json"
	editor.find_child("SaveTerrain", true, false).pressed.emit()
	_check(editor._dialog.visible and editor._dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE, "Save button must open the save dialog.")
	editor._dialog.hide()
	editor._dialog.file_selected.emit(path)
	_check(FileAccess.file_exists(path), "Runtime save dialog callback must write the visible terrain.")
	terrain.map_seed = "777"
	terrain.regenerate()
	editor.find_child("LoadTerrain", true, false).pressed.emit()
	_check(editor._dialog.visible and editor._dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE, "Load button must open the load dialog.")
	editor._dialog.hide()
	editor._dialog.file_selected.emit(path)
	_check(original == terrain.height_samples, "Loading must restore exact saved samples.")
	_check(terrain.terrain_template == "Mediterranean", "Loading must restore recipe settings.")
	_check(Document.save_file(path, terrain).is_empty() and FileAccess.file_exists(path + ".bak"), "Overwriting must preserve the previous save in a backup.")
	var bad: Dictionary = Document.capture(terrain)
	bad.settings.resolution = 1000000
	_check(not Document.apply(terrain, bad).is_empty() and original == terrain.height_samples, "Invalid files must be rejected without changing terrain.")
	bad = Document.capture(terrain)
	bad.heights.pop_back()
	_check(not Document.validate(bad).is_empty(), "Truncated sample arrays must be rejected.")
	bad = Document.capture(terrain)
	bad.settings.elevation = "30"
	_check(not Document.validate(bad).is_empty(), "Wrong setting types must be rejected.")
	var invalid_path: String = "res://.godot/invalid-terrain.json"
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid_file.store_string("{bad json")
	invalid_file.close()
	_check(not editor.load_terrain(invalid_path).is_empty() and original == terrain.height_samples, "Malformed JSON loads must leave the visible terrain unchanged.")
	DirAccess.remove_absolute(invalid_path)
	var png_path: String = "res://.godot/export-check.png"
	editor._dialog_action = "export"
	editor._file_selected(png_path)
	var png := Image.new()
	_check(png.load(png_path) == OK and png.get_size() == terrain.sample_size(), "Heightmap export must create a readable image of the grid.")
	var pixel: Color = png.get_pixel(32, 32)
	_check(is_equal_approx(pixel.r, pixel.g) and is_equal_approx(pixel.g, pixel.b), "Heightmap preview/export must be grayscale, not red-channel-only.")
	DirAccess.remove_absolute(png_path)
	var image := Image.create(3, 2, false, Image.FORMAT_RF)
	image.fill(Color(0.47, 0.47, 0.47))
	terrain.heightmap_texture = ImageTexture.create_from_image(image)
	terrain.source_heightmap_path = "test heightmap.exr"
	terrain.source_heightmap_size = Vector2i(3, 2)
	terrain.regenerate()
	var image_heights: PackedFloat32Array = terrain.height_samples.duplicate()
	_check(Document.save_file(path, terrain).is_empty(), "Imported images must be saveable.")
	terrain.heightmap_texture = null
	terrain.regenerate()
	var image_load_error: String = editor.load_terrain(path)
	_check(image_load_error.is_empty(), "Saved image inputs must load without their original file: " + image_load_error)
	_check(image_heights == terrain.height_samples and terrain.heightmap_texture != null, "Image input and visible heights must survive a round trip.")
	_check(terrain.source_heightmap_path == "test heightmap.exr" and terrain.source_heightmap_size == Vector2i(3, 2), "Original image provenance must survive a round trip.")
	var imported_path := "res://.godot/import-height-check.png"
	var imported := Image.create(4, 2, false, Image.FORMAT_RGB8)
	imported.fill(Color(0.65, 0.65, 0.65))
	imported.save_png(imported_path)
	editor._dialog_action = "image"
	editor._file_selected(imported_path)
	_check(terrain.height_samples == image_heights and picker.selected == editor._custom_index, "Importing a heightmap must stage the image without replacing the visible map.")
	editor.apply_settings()
	_check(terrain.heightmap_texture != null and terrain.source_heightmap_size == Vector2i(4, 2) and terrain.source_heightmap_path == imported_path and not terrain.island_enabled, "Generating an imported image must preserve its source and automate image settings.")
	for i in range(picker.item_count):
		if picker.get_item_text(i) == "High Island":
			picker.select(i)
			picker.item_selected.emit(i)
	_check(editor._pending_image == null, "Choosing a built-in heightmap must clear the staged custom image.")
	DirAccess.remove_absolute(imported_path)
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		editor.load_terrain(path + ".bak")
		for title in ["Volcano", "Archipelago", "Mediterranean", "High Island", "World heightmap"]:
			for i in range(picker.item_count):
				if picker.get_item_text(i) == title:
					picker.select(i)
					picker.item_selected.emit(i)
			editor.apply_settings()
			camera._reset_view()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/editor-%s.png" % title.to_lower().replace(" ", "-"))
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	if OS.get_cmdline_user_args().has("--capture-options") and DisplayServer.get_name() != "headless":
		for i in range(picker.item_count):
			if picker.get_item_text(i) == "Archipelago":
				picker.select(i)
				picker.item_selected.emit(i)
		editor.apply_settings()
		await process_frame
		var island_cell: int = -1
		for feature in terrain.geography.features:
			if feature.kind == "island" and feature.cell_count > 3:
				island_cell = feature.first_cell
				break
		_check(island_cell >= 0, "The GPU example must contain a labelled island.")
		if island_cell >= 0:
			var site: Vector2 = terrain.graph.points[island_cell] / terrain.map_size
			var location: Vector2 = (site - Vector2(0.5, 0.5)) * terrain.map_size
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = camera._camera.unproject_position(Vector3(location.x, terrain.surface_height(site), location.y))
			editor._unhandled_input(click)
			_check(editor._cell_label.text.contains("Island #"), "Clicking an island must show its new label in the real inspector.")
		var zoom_scroll: ScrollContainer = editor._form.get_parent()
		zoom_scroll.ensure_control_visible(editor._zoom_status)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/editor-zoom-islands.png")
	world.queue_free()
	await process_frame
	print("Runtime terrain editor checks: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
