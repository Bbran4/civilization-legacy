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
	layer.size = Vector2i(64, 40)
	layer.source_hash = "a".repeat(64)
	layer.ids.resize(64 * 40)
	for y in range(4, 36):
		for x in range(2, 25): layer.ids[y * 64 + x] = 1
	for y in range(12, 17):
		for x in range(40, 45): layer.ids[y * 64 + x] = 2
	for y in range(24, 29):
		for x in range(50, 55): layer.ids[y * 64 + x] = 3
	layer.records.assign([{"id":1,"kind":"land","name":"Mainland"},{"id":2,"kind":"land","name":"Little Isle"},{"id":3,"kind":"land","name":"Other Isle"}])
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
	var history := History.new()
	history.begin(layer, 1)
	history.stroke(Vector2(40, 14), Vector2(40, 14), 0.5, true)
	var result := history.finish()
	check(result.error.is_empty() and result.layer != null, "Touching a separate island commits whole-island attachment.")
	var attached: RefCounted = result.layer
	var all_owned := true
	for i in range(original.size()):
		if original[i] == 2: all_owned = all_owned and attached.ids[i] == 1
		elif original[i] == 0: all_owned = all_owned and attached.ids[i] == 0
	check(all_owned and layer.ids == original, "Entire island joins the mainland ID without filling sea or changing the installed original.")
	check(not attached.records[1].active and attached.records[1].name == "Little Isle" and attached.records[0].active and attached.records[2].active and attached.records[0].parts == 2, "Absorbed island ID is archived while target and other IDs stay stable.")
	check(attached.validate_coverage(base, 0.2, water).is_empty(), "Multi-island provinces retain exact land/water coverage.")
	var disk := Provinces.decode(JSON.parse_string(JSON.stringify(attached.snapshot())))
	check(disk.error.is_empty() and disk.layer.ids == attached.ids and not disk.layer.records[1].active and disk.layer.records[0].parts == 2, "Multi-part and absorbed state restores exactly through JSON.")
	var undone := history.undo(attached)
	check(undone.error.is_empty() and undone.layer.ids == original and undone.layer.records[1].active and undone.layer.records[1].name == "Little Isle", "Undo restores the absorbed island ID, name and full raster.")
	var redone := history.redo(undone.layer)
	check(redone.error.is_empty() and redone.layer.ids == attached.ids and not redone.layer.records[1].active, "Redo repeats island absorption exactly.")
	check(not history.begin(redone.layer, 2), "Archived province IDs cannot be paint targets.")
	history.begin(redone.layer, 3)
	history.stroke(Vector2(10, 10), Vector2(42, 14), 0.5, true)
	var chained := history.finish()
	check(chained.error.is_empty() and not chained.layer.records[0].active and not chained.layer.records[1].active and chained.layer.records[2].parts == 3, "A second island absorption preserves previously archived IDs.")
	var chain_undo := history.undo(chained.layer)
	check(chain_undo.layer.ids == attached.ids and chain_undo.layer.records[0].active and not chain_undo.layer.records[1].active, "Undo correctly restores the earlier multi-island province in a chain.")
	history.begin(layer, 1)
	history.stroke(Vector2(40, 14), Vector2(40, 14), 0.5, false)
	var partial := history.finish()
	check(partial.error.is_empty() and partial.layer.records[1].active and partial.layer.records[0].parts == 2, "Pixel painting can assign a partial island without requiring a sea bridge.")
	# Existing physical mainland border edits must not annex the whole landmass.
	var mainland := fixture()
	mainland.records.append({"id":4,"name":"Eastern Mainland","kind":"land"})
	for y in range(4, 36):
		for x in range(15, 25): mainland.ids[y * 64 + x] = 4
	mainland._index_regions()
	history.begin(mainland, 1)
	history.stroke(Vector2(15, 20), Vector2(16, 21), 1, true)
	var border := history.finish()
	check(border.error.is_empty() and border.layer.records[3].active and border.layer.ids[10 * 64 + 20] == 4, "Attach-islands mode keeps ordinary mainland border strokes local.")
	history.begin(mainland, 1)
	history.stroke(Vector2(21, 20), Vector2(21, 20), 0.5, true)
	check(not history.finish().error.is_empty(), "Disconnected enclaves on the same mainland remain invalid.")
	var maritime: RefCounted = attached.editable_copy()
	check(maritime.generate_oceans(base, water, 6, "coastal").is_empty(), "Coastal maritime partition grows around the authored islands.")
	var anchored := true
	for record in maritime.records:
		if record.kind != "ocean" or not record.active: continue
		var coast := false
		for neighbor in record.neighbors:
			coast = coast or maritime.records[neighbor - 1].kind == "land"
		anchored = anchored and coast
	check(anchored and maritime.ocean_style == "coastal" and not maritime.records[1].active, "Maritime regions anchor at coastlines and preserve absorbed land IDs.")
	var repeat: RefCounted = attached.editable_copy()
	repeat.generate_oceans(base, water, 6, "coastal")
	check(repeat.ids == maritime.ids, "Coastal partition is deterministic.")
	var open: RefCounted = attached.editable_copy()
	open.generate_oceans(base, water, 6, "open")
	check(open.ocean_style == "open" and open.ids != maritime.ids, "Open sea zones remain a separate selectable partition.")
	water.mask_bytes[(0 * 64 + 5) * 4 + 1] = 255
	var inland := base.duplicate()
	inland[15 * 64 + 15] = 0.1
	var classes := Provinces.classify(inland, 0.2, water.mask_bytes, layer.size)
	check(classes[5] == 0 and classes[15 * 64 + 15] == 3, "Generated lakes and enclosed low-elevation water have distinct classes.")
	water.mask_bytes[5 * 4 + 1] = 0
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	world.get_node("Terrain").resolution = 255 if DisplayServer.get_name() == "headless" else 1024
	root.add_child(world)
	await process_frame
	var editor = world.get_node("Interface/Editor")
	var terrain = world.get_node("Terrain")
	if DisplayServer.get_name() == "headless":
		terrain.resolution = 255
		terrain.regenerate()
		editor._sync_from_terrain()
	await editor.generate_water_layer()
	await editor.build_terrain_surface()
	editor._select_layer("provinces")
	await editor.generate_provinces()
	check(editor._province_brush.attach_islands.button_pressed and editor._ocean_style.get_item_metadata(editor._ocean_style.selected) == "coastal_band", "New editor defaults enable whole-island attachment and coastal maritime mode.")
	var installed: RefCounted = terrain.province_layer
	var target := 1
	for record in installed.records:
		if record.kind == "land" and record.pixels > installed.records[target - 1].pixels: target = record.id
	var islands: Dictionary = {}
	for i in range(installed.ids.size()):
		var mass: int = installed._land_components[i]
		if mass > 0 and mass not in installed.records[target - 1].landmasses:
			if not islands.has(mass): islands[mass] = {"pixels": 0, "seed": i}
			islands[mass].pixels += 1
	var chosen := -1
	for mass in islands:
		if chosen < 0 or islands[mass].pixels < islands[chosen].pixels: chosen = mass
	check(chosen > 0, "Template fixture supplies a separate island to attach.")
	var pixel: int = islands[chosen].seed
	var old_id: int = installed.ids[pixel]
	var old_name: String = installed.records[old_id - 1].name
	editor._select_province(target)
	var brush = editor._province_brush
	brush.history.begin(installed, target)
	brush.history.stroke(Vector2(pixel % installed.size.x, pixel / installed.size.x), Vector2(pixel % installed.size.x, pixel / installed.size.x), 0.5, true)
	brush.painting = true
	brush.finish()
	check(terrain.province_layer.ids[pixel] == target and not terrain.province_layer.records[old_id - 1].active, "Real template island attaches through the editor without changing the target ID.")
	brush.undo()
	check(terrain.province_layer.ids[pixel] == old_id and terrain.province_layer.records[old_id - 1].active and terrain.province_layer.records[old_id - 1].name == old_name, "Editor Undo restores the original island and name.")
	brush.redo()
	check(terrain.province_layer.ids[pixel] == target and not terrain.province_layer.records[old_id - 1].active, "Editor Redo reattaches the island.")
	await editor.generate_ocean_borders()
	check(not terrain.province_layer.records[old_id - 1].active and terrain.province_layer.ids[pixel] == target, "Maritime generation preserves authored multi-island province assignments.")
	check(terrain.province_layer.ocean_style == "coastal_band", "Ocean worker installs the selected maritime mode.")
	check(Document.save_file("res://.test-runtime/island_maritime_smoke-maritime.terrain.json", terrain).is_empty(), "Maritime maps save through the world terrain format.")
	var saved := Document.load_file("res://.test-runtime/island_maritime_smoke-maritime.terrain.json")
	check(saved.ok and Document.apply(terrain, saved.document).is_empty() and terrain.province_layer.ocean_style == "coastal_band", "Maritime mode and regions restore through disk.")
	check(not terrain.province_layer.records[old_id - 1].active and terrain.province_layer.ids[pixel] == target, "Disk restoration preserves absorbed island records and IDs.")
	if DisplayServer.get_name() != "headless":
		editor._sync_from_terrain()
		editor._select_province(target)
		await process_frame
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("ISLAND_OUTPUT")
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("islands-maritime-workspace.png"))
		var scroll: Node = editor._contexts.provinces
		while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
		if scroll != null: scroll.scroll_vertical = 9999
		await process_frame
		await RenderingServer.frame_post_draw
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("island-attachment-controls.png"))
	world.queue_free()
	await process_frame
	print("Island attachment and maritime regions: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
