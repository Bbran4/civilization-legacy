extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const History = preload("res://scripts/domain/province_edit_history.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func fixture() -> RefCounted:
	var layer := Provinces.new()
	layer.size = Vector2i(32, 24)
	layer.source_hash = "a".repeat(64)
	layer.ids.resize(32 * 24)
	for y in range(4, 24):
		for x in range(32): layer.ids[y * 32 + x] = 1 if x < 16 else 2
	layer.records.assign([{"id":1,"name":"West","kind":"land"},{"id":2,"name":"East","kind":"land"}])
	layer._index_regions()
	return layer
func _run() -> void:
	var layer := fixture()
	var base := PackedFloat32Array()
	base.resize(layer.ids.size())
	for i in range(base.size()): base[i] = 0.1 if layer.ids[i] == 0 else 0.6
	var water := Water.new()
	water.mask_size = layer.size
	water.mask_bytes.resize(base.size() * 4)
	var before: PackedInt32Array = layer.ids.duplicate()
	var ocean: RefCounted = layer.editable_copy()
	check(ocean.generate_oceans(base, water, 3, "coastal").is_empty(), "Ocean borders generate around land.")
	var classes_ok := true
	for i in range(before.size()):
		if before[i] > 0: classes_ok = classes_ok and ocean.ids[i] == before[i]
		else: classes_ok = classes_ok and ocean.ids[i] > 2 and ocean.records[ocean.ids[i] - 1].kind == "ocean"
	check(classes_ok and ocean.records[0].name == "West", "Ocean generation preserves all land IDs and names.")
	check(ocean.validate_coverage(base, 0.2, water).is_empty(), "Mixed land/ocean coverage validates.")
	var repeat: RefCounted = layer.editable_copy()
	repeat.generate_oceans(base, water, 3, "coastal")
	check(repeat.ids == ocean.ids, "Ocean borders are deterministic.")
	var decoded := Provinces.decode(JSON.parse_string(JSON.stringify(ocean.snapshot())))
	check(decoded.error.is_empty() and decoded.layer.ids == ocean.ids and decoded.layer.records == ocean.records, "Mixed region IDs, kinds and neighbors round-trip exactly.")
	var legacy: Dictionary = layer.snapshot()
	legacy.version = 1
	legacy.erase("ocean_generated")
	legacy.erase("requested_oceans")
	for record in legacy.records: record.erase("kind")
	check(Provinces.decode(legacy).error.is_empty(), "Older land-only province documents still load.")
	# A below-sea-level inland depression must not become ocean; lakes are excluded too.
	var enclosed := base.duplicate()
	enclosed[10 * 32 + 10] = 0.1
	water.mask_bytes[1 * 32 * 4 + 1] = 255
	var classification := Provinces.classify(enclosed, 0.2, water.mask_bytes, layer.size)
	check(classification[10 * 32 + 10] == 3 and classification[32] == 0 and classification[0] == 2, "Ocean flood excludes inland water and explicit lakes.")
	water.mask_bytes[1 * 32 * 4 + 1] = 0
	var history := History.new()
	check(history.begin(layer, 1), "A target region can begin a stroke.")
	history.stroke(Vector2(15, 8), Vector2(17, 12), 2)
	check(layer.ids == before, "Draft painting never mutates installed IDs.")
	layer.records[0].name = "West renamed during draft"
	var result := history.finish()
	check(result.error.is_empty() and result.layer != null and result.layer.ids != before, "A continuous connected border stroke commits.")
	check(result.layer.records[0].name == "West renamed during draft", "Committing borders preserves separately edited names.")
	var painted: PackedInt32Array = result.layer.ids.duplicate()
	var undone := history.undo(result.layer)
	check(undone.error.is_empty() and undone.layer.ids == before, "Undo restores exact raster IDs.")
	var redone := history.redo(undone.layer)
	check(redone.error.is_empty() and redone.layer.ids == painted, "Redo restores exact edited IDs.")
	history.begin(redone.layer, 1)
	history.stroke(Vector2(15, 15), Vector2(16, 18), 1.5)
	var next := history.finish()
	check(next.error.is_empty() and history.redo_stack.is_empty(), "A new stroke clears redo history.")
	history.sync(layer)
	history.begin(layer, 1)
	history.stroke(Vector2(24, 12), Vector2(24, 12), 1)
	check(not history.finish().error.is_empty() and layer.ids == before, "Disconnected target islands are rejected atomically.")
	history.begin(layer, 1)
	history.stroke(Vector2(20, 4), Vector2(20, 23), 1)
	check(not history.finish().error.is_empty(), "Splitting a donor region is rejected.")
	history.begin(layer, 1)
	history.stroke(Vector2(20, 12), Vector2(20, 12), 64)
	var absorbed := history.finish()
	check(absorbed.error.is_empty() and not absorbed.layer.records[1].active, "Painting over a land region absorbs it without renumbering IDs.")
	history.begin(ocean, 1)
	history.stroke(Vector2(0, 0), Vector2(31, 0), 3)
	check(history.changes.is_empty(), "Land painting cannot overwrite ocean pixels.")
	history.cancel()
	history.begin(ocean, 3)
	history.stroke(Vector2(5, 10), Vector2(25, 10), 2)
	check(history.changes.is_empty(), "Ocean painting cannot overwrite land pixels.")
	history.cancel()
	history.begin(layer, 1)
	history.stroke(Vector2(15, 10), Vector2(17, 12), NAN)
	history.stroke(Vector2(15, 10), Vector2(17, 12), -1)
	check(history.changes.is_empty(), "Invalid brush radii cannot mutate draft data.")
	history.cancel()
	var edited_ocean: RefCounted = ocean.editable_copy()
	var mixed_history := History.new()
	mixed_history.begin(edited_ocean, 1)
	mixed_history.stroke(Vector2(15, 8), Vector2(17, 12), 2)
	var mixed := mixed_history.finish()
	check(mixed.error.is_empty() and mixed.layer.validate_coverage(base, 0.2, water).is_empty() and Provinces.decode(mixed.layer.snapshot()).layer.ids == mixed.layer.ids, "Edited mixed-region IDs preserve coverage and round-trip exactly.")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	world.get_node("Terrain").resolution = 255
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	if DisplayServer.get_name() == "headless":
		terrain.resolution = 255
		terrain.regenerate()
		editor._sync_from_terrain()
	await editor.generate_water_layer()
	await editor.build_terrain_surface()
	editor._select_layer("provinces")
	await editor.generate_provinces()
	var land_ids: PackedInt32Array = terrain.province_layer.ids.duplicate()
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	await editor.generate_ocean_borders()
	check(terrain.province_layer_current() and terrain.province_layer.ocean_generated and terrain.height_samples == heights, "Integrated ocean generation preserves terrain and installs current regions.")
	var land_kept := true
	for i in range(land_ids.size()):
		if land_ids[i] > 0: land_kept = land_kept and terrain.province_layer.ids[i] == land_ids[i]
	check(land_kept, "Ocean generation does not replace authored land IDs.")
	check(Document.save_file("res://.test-runtime/ocean_border_paint_smoke-oceans.terrain.json", terrain).is_empty(), "Mixed ocean/land maps save.")
	var disk := Document.load_file("res://.test-runtime/ocean_border_paint_smoke-oceans.terrain.json")
	check(disk.ok and Document.apply(terrain, disk.document).is_empty() and terrain.province_layer.ocean_generated, "Ocean kinds and coverage restore from disk.")
	# Exercise the actual brush adapter against a known valid installed source.
	var custom := fixture()
	custom.source_hash = terrain.terrain_surface.fingerprint()
	custom.size = terrain.sample_size()
	custom.ids.resize(custom.size.x * custom.size.y)
	for y in range(custom.size.y):
		for x in range(custom.size.x): custom.ids[y * custom.size.x + x] = 1 if x < custom.size.x / 2 else 2
	custom._index_regions()
	terrain.install_province_layer(custom)
	var brush = editor._province_brush
	editor._select_province(1)
	brush.history.begin(custom, 1)
	brush.history.stroke(Vector2(custom.size.x / 2 - 1, 90), Vector2(custom.size.x / 2 + 2, 100), 2)
	brush.painting = true
	brush.finish()
	check(terrain.province_layer != custom and editor.dirty, "Brush adapter installs only a validated draft and marks edits dirty: " + brush.status.text)
	brush.undo()
	check(terrain.province_layer.ids == custom.ids, "UI Undo restores exact original border IDs.")
	brush.redo()
	check(terrain.province_layer.ids != custom.ids, "UI Redo restores the edit.")
	# Exercise screen-to-raster gestures through the real adapter.
	brush.enabled.button_pressed = true
	brush.radius.value = 8
	var camera: Camera3D = editor._camera_rig._camera
	var extent: Vector2 = terrain.display_size()
	var start := camera.unproject_position(terrain.to_global(Vector3(-0.002 * extent.x, 0, -0.1 * extent.y)))
	var end := camera.unproject_position(terrain.to_global(Vector3(0.008 * extent.x, 0, -0.08 * extent.y)))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start
	check(brush.handle_input(down) and brush.painting, "Screen-space mouse press begins a paint draft.")
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	check(brush.handle_input(motion), "Mouse motion paints a continuous screen-projected stroke.")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = end
	brush._input(up)
	check(not brush.painting, "Global mouse release finishes a stroke even over UI.")
	# A loaded/replaced province model cannot receive an old draft.
	brush.history.begin(terrain.province_layer, 1)
	brush.history.stroke(Vector2(127, 70), Vector2(129, 80), 2)
	brush.painting = true
	var replacement: RefCounted = terrain.province_layer.editable_copy()
	terrain.install_province_layer(replacement)
	brush.finish()
	check(terrain.province_layer == replacement and not brush.painting, "Replacing the document's region model cancels an obsolete stroke.")
	editor._layer_buttons.provinces[1].button_pressed = true
	var protected: RefCounted = terrain.province_layer
	brush.undo()
	await editor.generate_ocean_borders()
	check(terrain.province_layer == protected and not brush.painting, "Locks block paint/undo/ocean generation and stop strokes.")
	editor._layer_buttons.provinces[1].button_pressed = false
	# Reload the genuine authored map before screenshots and stale-job checks.
	Document.apply(terrain, disk.document)
	if DisplayServer.get_name() != "headless":
		editor._controls.heightmap_resolution.value = 1025
		editor.apply_settings()
		await editor.generate_water_layer()
		await editor.build_terrain_surface()
		await editor.generate_provinces()
		await editor.generate_ocean_borders()
		await process_frame
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("BORDER_OUTPUT")
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("ocean-borders-workspace.png"))
		check(terrain.map_renderer.material.get_shader_parameter("provinces_enabled"), "Actual GPU renders ocean and land region IDs.")
		var scroller: Node = editor._contexts.provinces
		while scroller != null and not scroller is ScrollContainer: scroller = scroller.get_parent()
		if scroller != null: scroller.scroll_vertical = 9999
		await process_frame
		await RenderingServer.frame_post_draw
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("border-brush-controls.png"))
		editor.play_map()
		await process_frame
		var player = editor._gameplay_map.get_node("Terrain")
		var toggle: CheckButton
		for control in editor._gameplay_map.get_node("MapHUD").get_child(0).get_children():
			if control is CheckButton: toggle = control
		check(toggle != null, "Gameplay exposes its political-view control.")
		toggle.button_pressed = true
		await RenderingServer.frame_post_draw
		check(player.map_renderer.material.get_shader_parameter("provinces_enabled") and player.province_layer.ocean_generated and player.province_layer.ids == terrain.province_layer.ids, "Gameplay receives exact edited land/ocean region data.")
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("ocean-borders-gameplay.png"))
		editor._return_from_map()
		await process_frame
	editor.generate_ocean_borders()
	await process_frame
	editor._water_job_serial += 1
	var retained = terrain.province_layer
	while editor._province_busy: await process_frame
	check(terrain.province_layer == retained, "A replaced document rejects pending ocean generation.")
	editor.generate_ocean_borders()
	await process_frame
	world.queue_free()
	await process_frame
	print("Ocean borders and painting: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
