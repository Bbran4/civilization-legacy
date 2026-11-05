extends SceneTree
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
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
	editor._controls["map_size.x"].value = 256
	editor._controls["map_size.y"].value = 256
	editor._controls.heightmap_resolution.value = 2050
	editor._controls.coast_detail.value = 0
	editor._controls.mountain_detail.value = 0
	editor.apply_settings()
	await terrain.wait_for_presentation()
	check(terrain.sample_size() == Vector2i(2050, 2050) and terrain.height_samples.size() == 2050 * 2050, "Maximum map is exactly 2050 pixels on the longest edge.")
	check(terrain.get_node("Surface").mesh is PlaneMesh, "Maximum output retains the bounded shared renderer, not millions of mesh triangles.")
	print("2050: display ready")
	editor._select_layer("rivers")
	editor._water_controls.routing_resolution.select(0)
	await editor.generate_water_layer()
	check(terrain.water_layer_current() and terrain.water_layer.mask_size == terrain.sample_size(), "Maximum-resolution water matches the full heightmap raster.")
	print("2050: water ready")
	await editor.build_terrain_surface()
	check(terrain.terrain_surface_current() and terrain.terrain_surface.heights.size() == 2050 * 2050, "Maximum surface builds at full output resolution.")
	print("2050: surface ready")
	await editor.generate_provinces()
	check(terrain.province_layer_current() and terrain.province_layer.ids.size() == 2050 * 2050, "Province ownership matches the maximum output raster.")
	print("2050: provinces ready")
	await editor.generate_ocean_borders()
	check(terrain.province_layer.ocean_generated, "Ocean regions generate at full 2050 resolution.")
	# A closed cut within an interior land block exercises new IDs after sea IDs at maximum size.
	var region_layer: RefCounted = terrain.province_layer
	var center := Vector2i(-1,-1)
	var split_id := 0
	for y in range(5,region_layer.size.y-5,7):
		if split_id > 0: break
		for x in range(5,region_layer.size.x-5,7):
			var id: int = region_layer.ids[y*region_layer.size.x+x]
			if id == 0 or region_layer.records[id-1].kind != "land": continue
			var interior := true
			for dy in range(-4,5):
				for dx in range(-4,5): interior = interior and region_layer.ids[(y+dy)*region_layer.size.x+x+dx] == id
			if interior:
				center = Vector2i(x,y)
				split_id = id
				break
	check(split_id > 0, "Maximum map supplies an interior province split fixture.")
	var edits := preload("res://scripts/domain/province_edit_history.gd").new()
	var c := Vector2(center)
	var split_result := edits.split(region_layer,split_id,PackedVector2Array([c+Vector2(-2,-2),c+Vector2(2,-2),c+Vector2(2,2),c+Vector2(-2,2),c+Vector2(-2,-2)]))
	check(split_result.error.is_empty() and terrain.install_province_layer(split_result.layer).is_empty(), "Province split installs at full 2050 resolution.")
	var created_id: int = split_result.new_id
	var restored_edit := edits.undo(terrain.province_layer)
	check(restored_edit.error.is_empty() and restored_edit.layer.ids == region_layer.ids, "Maximum-resolution split Undo is exact.")
	var repeated_edit := edits.redo(restored_edit.layer)
	terrain.install_province_layer(repeated_edit.layer)
	check(terrain.province_layer.records[created_id-1].active, "Maximum-resolution split Redo preserves the allocated ID.")
	edits.begin_erase(terrain.province_layer)
	edits.stroke(c,c,0.5)
	var erased := edits.finish()
	terrain.install_province_layer(erased.layer)
	var blocked_pixel: int = center.y*terrain.sample_size().x+center.x
	check(terrain.province_layer.blocked(blocked_pixel) and terrain.province_layer.ids[blocked_pixel] == 0, "Impassable erasure installs at maximum resolution.")
	var unerased := edits.undo(terrain.province_layer)
	check(unerased.layer.ids[blocked_pixel] == created_id and not unerased.layer.blocked(blocked_pixel), "Maximum erasure Undo restores ID and passability.")
	var re_erased := edits.redo(unerased.layer)
	terrain.install_province_layer(re_erased.layer)
	print("2050: edit history ready")
	var path := "user://maximum-water.terrain.json"
	check(Document.save_file(path, terrain).is_empty(), "Maximum-size height and water data fit the expanded bounded save format.")
	var result := Document.load_file(path)
	check(result.ok and Document.apply(terrain, result.document).is_empty() and terrain.water_layer_current() and terrain.terrain_surface_current() and terrain.province_layer_current(), "Maximum-resolution water and terrain restore together.")
	check(terrain.province_layer.records[created_id-1].active and terrain.province_layer.records[created_id-1].kind == "land", "Appended land province restores after ocean records.")
	check(terrain.province_layer.blocked(blocked_pixel) and terrain.province_layer.ids[blocked_pixel] == 0, "Maximum map restores the impassable mask exactly.")
	print("2050: saved data restored")
	# Race protection: reject an in-flight result if the source changes.
	var previous_layer = terrain.water_layer
	editor.generate_water_layer()
	await process_frame
	check(editor._water_busy, "Water generation runs independently of UI processing.")
	editor._controls.map_seed.text = "different-during-water"
	editor._controls.heightmap_resolution.value = 256
	editor.apply_settings()
	while editor._water_busy:
		await process_frame
	check(terrain.water_layer == previous_layer and not terrain.water_layer_current(), "An obsolete background result cannot replace the retained water layer.")
	# A document replacement with identical height data is also a different editing session.
	var document := Document.capture(terrain)
	var legacy: Dictionary = document.duplicate(true)
	legacy.geography.source_hash = Graph.legacy_snapshot_fingerprint(legacy.graph, terrain.map_size, terrain.surface_smoothing)
	# Reproduce the old on-disk representation, whose JSON loses negative-zero signs.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(legacy, "", true, true))
	check(Document.validate(parsed).is_empty(), "Older signed-zero geography caches remain readable after JSON roundtrip.")
	var tampered: Dictionary = parsed.duplicate(true)
	tampered.graph.points[0][0] += 0.1
	check(not Document.validate(tampered).is_empty(), "Legacy compatibility does not bypass graph/cache integrity checks.")
	tampered = parsed.duplicate(true)
	tampered.graph.points[-1][0] += 1.0
	tampered.geography.source_hash = ""
	check(not Document.validate(tampered).is_empty(), "An empty legacy fallback cannot validate altered boundary geometry.")
	var copy_path := "user://same-height.terrain.json"
	check(Document.save_file(copy_path, terrain).is_empty(), "Document-switch fixture saves.")
	editor.generate_water_layer()
	await process_frame
	check(editor.load_terrain(copy_path).is_empty(), "A document may be opened while the old computation finishes.")
	while editor._water_busy:
		await process_frame
	check(not terrain.water_layer_current(), "A background result cannot install itself into a replacement document with the same heights.")
	editor.generate_water_layer()
	check(editor.load_terrain(copy_path).is_empty(), "A replacement may also occur before the worker starts.")
	while editor._water_busy:
		await process_frame
	check(not terrain.water_layer_current(), "A queued job is not rebound to a replacement document before native inputs commit.")
	world.queue_free()
	await process_frame
	print("Water resolution and background safeguards: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
