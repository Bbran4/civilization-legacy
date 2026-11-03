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
	layer.size = Vector2i(65,49)
	layer.source_hash = "a".repeat(64)
	layer.ids.resize(65 * 49)
	for y in range(8,41):
		for x in range(8,57): layer.ids[y * 65 + x] = 1
	layer.records.append({"id":1,"name":"Original","kind":"land"})
	layer._index_regions()
	return layer
func _run() -> void:
	var layer := fixture()
	var original: PackedInt32Array = layer.ids.duplicate()
	var base := PackedFloat32Array()
	base.resize(original.size())
	for i in range(base.size()): base[i] = 0.6 if original[i] > 0 else 0.1
	var water := Water.new()
	water.mask_size = layer.size
	water.mask_bytes.resize(base.size() * 4)
	layer.generate_oceans(base, water, 4, "coastal_band", 64)
	var full_original: PackedInt32Array = layer.ids.duplicate()
	var original_records: int = layer.records.size()
	var history := History.new()
	var result := history.split(layer, 1, PackedVector2Array([Vector2(27,4),Vector2(27,45)]))
	check(result.error.is_empty() and result.layer != null, "A complete border splits a province after ocean generation.")
	var split: RefCounted = result.layer
	var id: int = result.new_id
	check(id == original_records + 1 and split.records[0].name == "Original" and split.records[0].active and split.records[id - 1].kind == "land", "Split appends a new ID and preserves the original ID/name across interleaved kinds.")
	var protected := true
	for i in range(original.size()):
		if original[i] == 0: protected = protected and split.ids[i] == full_original[i]
	check(layer.ids == full_original and protected and split.validate_coverage(base, 0.2, water).is_empty(), "Split drafts preserve input, sea, coastline and complete land coverage.")
	var disk := Provinces.decode(JSON.parse_string(JSON.stringify(split.snapshot())))
	check(disk.error.is_empty() and disk.layer.ids == split.ids and disk.layer.records[id - 1].active, "Split IDs after ocean records restore through JSON.")
	var undone := history.undo(split)
	check(undone.error.is_empty() and undone.layer.ids == full_original and not undone.layer.records[id - 1].active, "Undo restores exact original pixels and archives the allocated ID.")
	var redone := history.redo(undone.layer)
	check(redone.error.is_empty() and redone.layer.ids == split.ids and redone.layer.records[id - 1].active, "Redo restores the same split ID.")
	redone.layer.records[id - 1].name = "Custom split name"
	var merged := history.merge(redone.layer, 1, [1,id])
	check(merged.error.is_empty() and merged.layer.ids == full_original and not merged.layer.records[id - 1].active and merged.layer.records[0].name == "Original", "Merge preserves kept ID/name and archives the donor.")
	var merge_undo := history.undo(merged.layer)
	check(merge_undo.error.is_empty() and merge_undo.layer.ids == split.ids and merge_undo.layer.records[id - 1].name == "Custom split name", "Undo merge restores exact borders and donor name.")
	var merge_redo := history.redo(merge_undo.layer)
	check(merge_redo.error.is_empty() and merge_redo.layer.ids == full_original, "Redo repeats merge exactly.")
	var regenerated: RefCounted = split.editable_copy()
	regenerated.generate_oceans(base, water, 4, "coastal_band", 64)
	var stable := true
	for i in range(split.ids.size()):
		if original[i] > 0: stable = stable and regenerated.ids[i] == split.ids[i]
	check(stable and regenerated.records[id - 1].active and Provinces.decode(regenerated.snapshot()).error.is_empty(), "Later ocean regeneration preserves appended land IDs and remains readable.")
	check(not history.split(layer, 1, PackedVector2Array([Vector2(10,10),Vector2(15,15)])).error.is_empty(), "An unfinished internal line cannot split a province.")
	check(not history.split(layer, 1, PackedVector2Array([Vector2(1,1),Vector2(2,2)])).error.is_empty(), "A line missing the selected province is rejected.")
	var loop := history.split(layer, 1, PackedVector2Array([Vector2(20,20),Vector2(30,20),Vector2(30,30),Vector2(20,30),Vector2(20,20)]))
	check(loop.error.is_empty(), "Closed-loop border drawing creates a province without holes in coverage.")
	var ocean_ids: Array[int] = []
	for record in layer.records:
		if record.kind == "ocean" and record.active: ocean_ids.append(record.id)
	check(not history.merge(layer, 1, [1,ocean_ids[0]]).error.is_empty(), "Mixed land/ocean merge is rejected.")
	check(not history.merge(layer, 1, [1]).error.is_empty(), "Merging a single province is rejected.")
	var stripes := fixture()
	stripes.records.append({"id":2,"kind":"land","name":"Middle"})
	stripes.records.append({"id":3,"kind":"land","name":"Far side"})
	for i in range(stripes.ids.size()):
		if stripes.ids[i] > 0: stripes.ids[i] = 1 if i % 65 < 24 else (2 if i % 65 < 40 else 3)
	stripes._index_regions()
	check(not history.merge(stripes,1,[1,3]).error.is_empty(), "Nonadjacent mainland provinces cannot form a disconnected merge.")
	var sea_only := Provinces.new()
	sea_only.size = Vector2i(17,17)
	sea_only.source_hash = "b".repeat(64)
	sea_only.ids.resize(17 * 17)
	var sea_base := PackedFloat32Array()
	sea_base.resize(sea_only.ids.size())
	sea_base.fill(0.1)
	var sea_water := Water.new()
	sea_water.mask_size = sea_only.size
	sea_water.mask_bytes.resize(sea_base.size() * 4)
	sea_only.generate_oceans(sea_base,sea_water,1,"open")
	var sea_split := history.split(sea_only,1,PackedVector2Array([Vector2(8,0),Vector2(8,16)]))
	check(sea_split.error.is_empty() and sea_split.layer.records[sea_split.new_id - 1].kind == "ocean", "Sea-region splits preserve ocean kind.")
	var sea_merge := history.merge(sea_split.layer,1,[1,sea_split.new_id])
	check(sea_merge.error.is_empty() and not sea_merge.layer.records[sea_split.new_id - 1].active and sea_merge.layer.validate_coverage(sea_base,0.2,sea_water).is_empty(), "Connected sea regions merge without converting sea or losing coverage.")
	var branch := History.new()
	var first := branch.split(layer,1,PackedVector2Array([Vector2(25,4),Vector2(25,45)]))
	var reverted := branch.undo(first.layer)
	var second := branch.split(reverted.layer,1,PackedVector2Array([Vector2(35,4),Vector2(35,45)]))
	check(second.error.is_empty() and second.new_id > first.new_id and not second.layer.records[first.new_id - 1].active and branch.redo_stack.is_empty(), "Branching after Undo reserves the old ID and allocates a new split ID.")
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
	check(brush.mode.item_count == 3, "Editor exposes paint, split and merge tools.")
	# Choose an actual land province and search a simple cut that yields two valid pieces.
	var source: RefCounted = terrain.province_layer
	var target := 1
	for record in source.records:
		if record.kind == "land" and record.pixels > source.records[target - 1].pixels: target = record.id
	var low: Vector2i = source.size
	var high := Vector2i.ZERO
	for i in range(source.ids.size()):
		if source.ids[i] == target:
			low = low.min(Vector2i(i % source.size.x, i / source.size.x))
			high = high.max(Vector2i(i % source.size.x, i / source.size.x))
	var cut := PackedVector2Array()
	var cuts: Array[int] = []
	for x in range(low.x + 2, high.x - 1): cuts.append(x)
	var center := (low.x + high.x) / 2
	cuts.sort_custom(func(a: int,b: int): return absi(a-center) < absi(b-center))
	for x in cuts:
		var probe := History.new()
		var points := PackedVector2Array([Vector2(x,low.y - 1),Vector2(x,high.y + 1)])
		if probe.split(source,target,points).error.is_empty():
			cut = points
			break
	check(cut.size() == 2, "Template fixture offers a valid split line.")
	editor._select_province(target)
	brush.mode.select(1)
	brush._set_mode(1)
	brush.enabled.button_pressed = true
	var camera: Camera3D = editor._camera_rig._camera
	var extent: Vector2 = terrain.display_size()
	var a: Vector2 = (cut[0] / Vector2(source.size - Vector2i.ONE) - Vector2.ONE * 0.5) * extent
	var b: Vector2 = (cut[1] / Vector2(source.size - Vector2i.ONE) - Vector2.ONE * 0.5) * extent
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = camera.unproject_position(terrain.to_global(Vector3(a.x,0,a.y)))
	check(brush.handle_input(down) and brush.painting, "Screen-space press begins split drawing.")
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(terrain.to_global(Vector3(b.x,0,b.y)))
	brush.handle_input(motion)
	brush._draw_split()
	check(brush.preview.visible and brush.split_points.size() >= 2, "Split border line is previewed before commit.")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	brush._input(release)
	var new_id: int = editor._province_selected
	check(new_id > source.records.size() and terrain.province_layer_current(), "Editor installs validated split and selects its new ID.")
	brush.undo()
	check(editor._province_selected == target and not terrain.province_layer.records[new_id-1].active, "Undo split selects the restored original province.")
	brush.redo()
	check(editor._province_selected == new_id and terrain.province_layer.records[new_id-1].active, "Redo split selects the same restored new ID.")
	check(Document.save_file("user://split-map.terrain.json", terrain).is_empty(), "Split map saves to disk.")
	var saved := Document.load_file("user://split-map.terrain.json")
	check(saved.ok and Document.apply(terrain, saved.document).is_empty() and terrain.province_layer.records[new_id - 1].active, "Split map restores exact IDs after ocean records.")
	editor._select_province(target)
	brush.mode.select(2)
	brush._set_mode(2)
	brush.enabled.button_pressed = true
	var donor_pixel := -1
	for i in range(terrain.province_layer.ids.size()):
		if terrain.province_layer.ids[i] == new_id:
			donor_pixel = i
			break
	var donor_point := (Vector2(donor_pixel % source.size.x,donor_pixel / source.size.x) / Vector2(source.size - Vector2i.ONE) - Vector2.ONE * 0.5) * extent
	down.position = camera.unproject_position(terrain.to_global(Vector3(donor_point.x,0,donor_point.y)))
	brush.handle_input(down)
	check(brush.merge_ids.size() == 2 and not brush.merge_action.disabled, "Merge selection includes kept and donor regions.")
	if DisplayServer.get_name() != "headless":
		var scroll: Node = editor._contexts.provinces
		while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
		if scroll != null: scroll.scroll_vertical = 9999
		await process_frame
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("SPLIT_OUTPUT")
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("province-merge-selection.png"))
	brush.merge_selected()
	check(not terrain.province_layer.records[new_id - 1].active and terrain.province_layer.records[target - 1].active, "Editor merge archives donor and preserves kept region.")
	brush.undo()
	check(terrain.province_layer.records[new_id - 1].active, "Editor Undo restores merged province.")
	brush.redo()
	check(not terrain.province_layer.records[new_id - 1].active, "Editor Redo repeats merge.")
	brush.undo()
	brush._toggle_merge(new_id)
	editor._layer_buttons.provinces[1].button_pressed = true
	var locked: RefCounted = terrain.province_layer
	brush.merge_selected()
	check(terrain.province_layer == locked and brush.merge_ids.is_empty(), "Locking blocks merging and clears selection.")
	editor._layer_buttons.provinces[1].button_pressed = false
	brush._toggle_merge(new_id)
	var replaced: RefCounted = terrain.province_layer.editable_copy()
	terrain.install_province_layer(replaced)
	brush.merge_selected()
	check(terrain.province_layer == replaced, "A replaced model rejects an obsolete merge selection.")
	world.queue_free()
	await process_frame
	print("Province split and merge: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
