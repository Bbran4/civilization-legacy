extends SceneTree
const Controls = preload("res://scripts/domain/regional_controls.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	_run.call_deferred()
func outside(forest: Node) -> Dictionary:
	var result := {}
	for i in range(forest.positions.size()):
		if forest.positions[i].x > 0.65: result[forest.positions[i]] = [forest.kinds[i],forest.scales[i]]
	return result
func capture() -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func _run() -> void:
	var invalid := Controls.DEFAULTS.duplicate()
	invalid.moisture = NAN
	check(not Controls.validate_settings(invalid).is_empty(),"Nonfinite regional adjustments fail validation")
	var world = load("res://scenes/main.tscn").instantiate()
	var terrain = world.get_node("Terrain")
	terrain.resolution = 128
	terrain.graph_points = 1000
	terrain.map_size = Vector2(96,72)
	root.add_child(world)
	await process_frame
	terrain.elevation = 12
	terrain.regenerate()
	var size: Vector2i = terrain.sample_size()
	var source := PackedFloat32Array()
	source.resize(size.x*size.y)
	source.fill((0.44-0.2)*12)
	terrain.restore_heightfield(source,size)
	var trees: Dictionary = terrain.tree_settings.duplicate()
	trees.count = 500
	trees.coverage = 100
	check(terrain.apply_tree_settings(trees).is_empty(),"Prepare regional forest")
	var editor = world.get_node("Interface/Editor")
	editor._sync_from_terrain()
	editor._show_regions()
	var panel = editor._regional_panel
	var controls = terrain.regional_controls
	check(panel.active() and editor.selected_layer == "paint","Regional context belongs to Ground paint without a new world layer")
	var baseline: PackedByteArray = controls.field(terrain.map_seed)._bytes.duplicate()
	var hash: String = terrain.water_source_hash
	var old_outside := outside(terrain.forest_view)
	check(old_outside.size() > 10,"Outside-selection forest fixture exists")
	panel.global_controls.warmth.value = 10
	panel.global_controls.moisture.value = 15
	await process_frame
	panel.apply_global()
	check(controls.settings.warmth == 10 and controls.field(terrain.map_seed)._bytes != baseline,"Whole-map controls commit typed warmth/moisture changes")
	panel.undo()
	check(controls.field(terrain.map_seed)._bytes == baseline,"Undo restores exact generated climate")
	panel.brush.button_pressed = true
	var camera: Camera3D = editor._camera_rig.get_node("Camera3D")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = camera.unproject_position(Vector3(-19.2,terrain.visible_surface_height(Vector2(0.3,0.5)),0))
	editor._unhandled_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = press.position
	editor._unhandled_input(release)
	check(panel.selection.count(0) < panel.selection.size() and not panel.painting,"Editor input routes a picked map selection and ends it on release")
	panel.selection.fill(0)
	panel.stamp(Vector2(0.5,0.5),Vector2(1024,512),1)
	check(panel.selection.count(0) < panel.selection.size(),"Small requested brush still covers regional samples on a large map")
	panel.selection.fill(0)
	panel.stamp(Vector2(0.3,0.5),Vector2(96,72),13)
	panel._refresh_selection()
	check(panel.selection.count(0) < panel.selection.size() and panel.selection[64*128+120] == 0,"Selection brush has bounded, local coverage")
	panel.local_controls.warmth.value = 20
	panel.local_controls.moisture.value = -40
	panel.local_controls.variation.value = 7
	await process_frame
	panel.apply_selected()
	var changed: PackedByteArray = controls.field(terrain.map_seed)._bytes.duplicate()
	var local_only := true
	var touched := 0
	for i in range(panel.selection.size()):
		for channel in range(2):
			if changed[i*4+channel] == baseline[i*4+channel]: continue
			if panel.selection[i] == 0: local_only = false
			touched += 1
	check(local_only and touched > 100,"Selected regeneration modifies only selected climate texels")
	check(outside(terrain.forest_view) == old_outside,"Local climate changes preserve trees outside the selected area")
	check(terrain.height_samples == source and terrain.water_source_hash == hash,"Regional edits preserve terrain and geography identity")
	var authored: PackedByteArray = controls.overrides.duplicate()
	panel.apply_selected(true)
	check(controls.field(terrain.map_seed)._bytes == baseline,"Reset selected returns to the generated field")
	panel.undo()
	check(controls.overrides == authored and outside(terrain.forest_view) == old_outside,"Undo restores regional overrides and stable outside trees")
	editor._layer_buttons.paint[1].button_pressed = true
	panel.apply_global()
	check(controls.overrides == authored and controls.settings == Controls.DEFAULTS,"Ground paint lock protects regional edits")
	editor._layer_buttons.paint[1].button_pressed = false
	panel.preview.select(1)
	panel.update_preview()
	check(terrain.region_preview == 1 and not terrain.forest_view.visible,"Warmth preview hides tree geometry for readable coverage")
	if DisplayServer.get_name() != "headless":
		var warmth := await capture()
		warmth.save_png("res://.test-runtime/regions-warmth.png")
		panel.preview.select(2)
		panel.update_preview()
		var moisture := await capture()
		moisture.save_png("res://.test-runtime/regions-moisture.png")
		check(warmth.get_data() != moisture.get_data(),"Warmth and moisture previews produce distinct GPU views")
		panel.preview.select(3)
		panel.update_preview()
		(await capture()).save_png("res://.test-runtime/regions-selection.png")
	editor._select_layer("paint")
	check(terrain.region_preview == 0 and terrain.forest_view.visible,"Leaving regional controls restores normal rendering")
	var field_key: String = controls.field(terrain.map_seed).key
	var positions: PackedVector2Array = terrain.forest_view.positions.duplicate()
	var save_error: String = editor.save_world("res://.test-runtime/regional-controls.world.json")
	check(save_error.is_empty(),"World save persists regional controls: "+save_error)
	check(editor.load_world("res://.test-runtime/regional-controls.world.json").is_empty(),"World reload restores authored regions")
	check(terrain.regional_controls.overrides == authored and terrain.regional_controls.field(terrain.map_seed).key == field_key and terrain.forest_view.positions == positions,"Save/load preserves local climate and exact derived forest positions")
	var saved: Dictionary = Document.capture(terrain)
	var bad := saved.duplicate(true)
	bad.regional_controls.overrides = "invalid"
	check(not Document.apply(terrain,bad).is_empty() and terrain.regional_controls.overrides == authored,"Malformed regional payload fails before changing live state")
	bad = saved.duplicate(true)
	bad.erase("regional_controls")
	check(not Document.validate(bad).is_empty(),"Current saves require regional controls")
	var legacy := saved.duplicate(true)
	legacy.version = 14
	legacy.erase("regional_controls")
	check(Document.apply(terrain,legacy).is_empty() and terrain.regional_controls.settings == Controls.DEFAULTS and terrain.regional_controls.overrides.count(0) == Controls.BYTES,"Older saves load default climate without authored edits")
	check(Document.apply(terrain,saved).is_empty(),"Restore authored regions")
	editor.play_map()
	await process_frame
	check(editor._gameplay_map != null and editor._gameplay_map.get_node("Terrain").regional_controls.overrides == authored and editor._gameplay_map.get_node("Terrain").region_preview == 0,"Gameplay uses saved regional edits without editor previews")
	editor._return_from_map()
	world.free()
	await process_frame
	print("Regional controls: %d failures" % failures)
	quit(1 if failures else 0)
