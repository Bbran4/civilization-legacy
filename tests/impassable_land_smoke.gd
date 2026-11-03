extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const History = preload("res://scripts/domain/province_edit_history.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func fixture() -> RefCounted:
	var layer := Provinces.new()
	layer.source_hash = "a".repeat(64)
	layer.size = Vector2i(65,49)
	layer.ids.resize(65*49)
	for y in range(8,41):
		for x in range(8,57): layer.ids[y*65+x] = 1 if x < 32 else 2
	layer.records.assign([{"id":1,"name":"West","kind":"land"},{"id":2,"name":"East","kind":"land"}])
	layer._index_regions()
	return layer
func _run() -> void:
	var layer := fixture()
	var base := PackedFloat32Array()
	base.resize(layer.ids.size())
	for i in range(base.size()): base[i] = 0.6 if layer.ids[i] > 0 else 0.1
	var water := Water.new()
	water.mask_size = layer.size
	water.mask_bytes.resize(base.size()*4)
	layer.generate_oceans(base,water,4)
	var original: PackedInt32Array = layer.ids.duplicate()
	var legacy: Dictionary = layer.snapshot()
	legacy.version = 5
	legacy.erase("impassable")
	for record in legacy.records: record.erase("allow_fragments")
	var old := Provinces.decode(legacy)
	check(old.error.is_empty() and old.layer.impassable.is_empty() and old.layer.ids == layer.ids, "V5 maps load without adding impassable zones or changing IDs.")
	var history := History.new()
	history.begin_erase(layer)
	history.stroke(Vector2(30,8),Vector2(33,40),2)
	check(layer.ids == original and layer.impassable.is_empty(), "Eraser drafts never mutate installed land or masks.")
	var erased := history.finish()
	check(erased.error.is_empty() and erased.layer != null, "A mountain-shaped land strip can be erased.")
	var model: RefCounted = erased.layer
	var count := 0
	var valid := true
	for i in range(model.ids.size()):
		if model.blocked(i):
			count += 1
			valid = valid and model.ids[i] == 0 and original[i] > 0 and layer.records[original[i]-1].kind == "land"
	check(valid and count > 50 and model.validate_coverage(base,0.2,water).is_empty(), "Erased land is explicitly impassable, unassigned and coverage-valid.")
	check(2 not in model.records[0].neighbors, "An erased shared border removes passable province adjacency.")
	var disk := Provinces.decode(JSON.parse_string(JSON.stringify(model.snapshot())))
	check(disk.error.is_empty() and disk.layer.impassable == model.impassable and disk.layer.ids == model.ids, "Impassable masks and border IDs restore exactly.")
	var undo := history.undo(model)
	check(undo.error.is_empty() and undo.layer.ids == original and not undo.layer.impassable.has(1), "Undo erasure restores exact IDs and passability.")
	var redo := history.redo(undo.layer)
	check(redo.error.is_empty() and redo.layer.ids == model.ids and redo.layer.impassable == model.impassable, "Redo restores exact impassable mask.")
	history.begin(redo.layer,1)
	history.stroke(Vector2(29,8),Vector2(33,40),3,false)
	var restored := history.finish()
	check(restored.error.is_empty() and not restored.layer.impassable.has(1) and restored.layer.validate_coverage(base,0.2,water).is_empty(), "Painting returns erased areas to province coverage and clears impassability.")
	var restore_undo := history.undo(restored.layer)
	check(restore_undo.layer.ids == model.ids and restore_undo.layer.impassable == model.impassable, "Undo repaint restores erased land.")
	var island := fixture()
	history.begin_erase(island)
	history.stroke(Vector2(8,20),Vector2(56,20),1)
	var divide := history.finish()
	check(divide.error.is_empty() and divide.layer.records[0].parts == 2, "An impassable ridge can separate passable parts without rejecting the edit.")
	check(divide.layer.records[0].landmasses.size() == 1, "A mountain barrier does not turn a continent into separate physical islands.")
	var connected := fixture()
	history.begin_erase(connected)
	history.stroke(Vector2(8,24),Vector2(31,24),0.5)
	var ridge := history.finish()
	check(ridge.error.is_empty() and ridge.layer.records[0].parts == 2, "A ridge can separate one province even when other provinces connect around it.")
	history.begin(ridge.layer,2)
	history.stroke(Vector2(8,24),Vector2(31,24),0.5,true)
	var other_restore := history.finish()
	check(other_restore.error.is_empty() and not other_restore.layer.impassable.has(1) and other_restore.layer.ids[24*65+20] == 2, "Erased land can be painted into a different selected province.")
	var policy_undo := history.undo(other_restore.layer)
	check(policy_undo.layer.blocked(24*65+20) and not policy_undo.layer.records[1].allow_fragments, "Undo restores both impassability and the prior land-part policy.")
	history.begin_erase(layer)
	history.stroke(Vector2(0,0),Vector2(64,0),5)
	check(history.changes.is_empty(), "Erasing never changes sea or unassigned water.")
	history.cancel()
	var corrupt: RefCounted = model.editable_copy()
	corrupt.impassable[0] = 1
	check(not corrupt.validate_coverage(base,0.2,water).is_empty(), "Sea cannot be imported as impassable land.")
	var all := fixture()
	history.begin_erase(all)
	history.stroke(Vector2(8,24),Vector2(56,24),32)
	var empty := history.finish()
	check(empty.error.is_empty() and not empty.layer.records[0].active and not empty.layer.records[1].active, "Completely erased provinces are archived without deleting names.")
	check(history.begin_new_land(empty.layer,20*65+20), "Erased land can start a new province when no active target remains.")
	history.stroke(Vector2(20,20),Vector2(23,23),2)
	var new_land := history.finish()
	check(new_land.error.is_empty() and new_land.layer.records[new_land.new_id-1].active and new_land.layer.ids[20*65+20] == new_land.new_id, "Painting with no selection creates valid fresh province coverage.")
	var fresh_undo := history.undo(new_land.layer)
	check(fresh_undo.layer.blocked(20*65+20) and not fresh_undo.layer.records[new_land.new_id-1].active, "Undo new restored land reestablishes its impassable zone.")
	var regenerated: RefCounted = model.editable_copy()
	regenerated.generate_oceans(base,water,4)
	check(regenerated.impassable == model.impassable and regenerated.validate_coverage(base,0.2,water).is_empty(), "Ocean regeneration preserves authored impassable land.")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	world.get_node("Terrain").resolution = 255 if DisplayServer.get_name() == "headless" else 1024
	root.add_child(world)
	await process_frame
	var editor = world.get_node("Interface/Editor")
	var terrain = world.get_node("Terrain")
	await editor.generate_water_layer()
	await editor.build_terrain_surface()
	editor._select_layer("provinces")
	await editor.generate_provinces()
	await editor.generate_ocean_borders()
	var brush = editor._province_brush
	check(brush.mode.item_count == 4, "Province tools include the impassable eraser.")
	var source: RefCounted = terrain.province_layer
	var target := 1
	for record in source.records:
		if record.kind == "land" and record.pixels > source.records[target-1].pixels: target = record.id
	var seed := -1
	var best := -1.0
	for i in range(source.ids.size()):
		if source.ids[i] == target and terrain.terrain_surface.heights[i] > best:
			best = terrain.terrain_surface.heights[i]
			seed = i
	var pixel := Vector2(seed % source.size.x,seed / source.size.x)
	brush.mode.select(3)
	brush._set_mode(3)
	brush.enabled.button_pressed = true
	editor._select_province(0)
	var erase_a: Vector2 = pixel - Vector2(10,0) * source.size.x/1025.0
	var erase_b: Vector2 = pixel + Vector2(20,8) * source.size.x/1025.0
	brush.radius.value = 8
	var erase_radius: float = brush.radius.value * source.size.x/1025.0
	var camera: Camera3D = editor._camera_rig._camera
	var extent: Vector2 = terrain.display_size()
	var a := (erase_a / Vector2(source.size-Vector2i.ONE)-Vector2.ONE*0.5)*extent
	var b := (erase_b / Vector2(source.size-Vector2i.ONE)-Vector2.ONE*0.5)*extent
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = camera.unproject_position(terrain.to_global(Vector3(a.x,0,a.y)))
	check(brush.handle_input(down) and brush.painting, "Eraser screen-space gesture starts without selecting a province.")
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(terrain.to_global(Vector3(b.x,0,b.y)))
	brush.handle_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	brush._input(up)
	check(terrain.province_layer.blocked(seed) and terrain.province_layer.ids[seed] == 0, "Editor erases mountain land into an impassable zone.")
	check(Document.save_file("user://impassable.terrain.json",terrain).is_empty(), "Impassable map saves through terrain document storage.")
	var saved := Document.load_file("user://impassable.terrain.json")
	check(saved.ok and Document.apply(terrain,saved.document).is_empty() and terrain.province_layer.blocked(seed), "Impassable map restores from disk.")
	brush.mode.select(0)
	brush._set_mode(0)
	brush.enabled.button_pressed = true
	editor._select_province(target)
	check(brush._begin_paint(pixel), "Paint tool can target erased mountain land.")
	brush.history.stroke(erase_a,erase_b,erase_radius,false)
	brush.painting = true
	brush.finish()
	check(not terrain.province_layer.blocked(seed) and terrain.province_layer.ids[seed] == target, "Editor repaint restores province IDs and passability.")
	brush.undo()
	check(terrain.province_layer.blocked(seed), "Editor Undo restores impassability.")
	editor._layer_buttons.provinces[1].button_pressed = true
	var locked: RefCounted = terrain.province_layer
	brush.redo()
	check(terrain.province_layer == locked, "Layer lock blocks erasure/restoration history actions.")
	editor._layer_buttons.provinces[1].button_pressed = false
	if DisplayServer.get_name() != "headless":
		brush.mode.select(3)
		brush._set_mode(3)
		var scroll: Node = editor._contexts.provinces
		while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
		if scroll != null: scroll.scroll_vertical = 9999
		await process_frame
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("IMPASSABLE_OUTPUT")
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("impassable-land-workspace.png"))
		editor.play_map()
		await process_frame
		var player = editor._gameplay_map.get_node("Terrain")
		for control in editor._gameplay_map.get_node("MapHUD").get_child(0).get_children():
			if control is CheckButton: control.button_pressed = true
		await RenderingServer.frame_post_draw
		check(player.province_layer.blocked(seed) and player.province_layer.ids[seed] == 0, "Gameplay receives exact impassable state.")
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("impassable-land-gameplay.png"))
		editor._return_from_map()
		await process_frame
	world.queue_free()
	await process_frame
	print("Impassable land eraser: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
