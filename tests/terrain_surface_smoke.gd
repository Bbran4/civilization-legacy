extends SceneTree
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Surface = preload("res://scripts/domain/terrain_surface.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
const Manifest = preload("res://scripts/storage/world_manifest.gd")
var failures := 0
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var size := Vector2i(129, 97)
	var base := PackedFloat32Array()
	base.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			var uv := Vector2(x, y) / Vector2(size - Vector2i.ONE)
			base[y * size.x + x] = 0.85 - uv.y * 0.8 + sin(uv.x * 18) * 0.015 - exp(-pow((uv.x - 0.5) / 0.12, 2) - pow((uv.y - 0.45) / 0.12, 2)) * 0.28
	var original := base.duplicate()
	var water := Water.new()
	check(water.generate(base, size, "a".repeat(64), Water.DEFAULTS).is_empty(), "Synthetic water builds.")
	var mask := water.mask_bytes.duplicate()
	var levels := water.surface_levels.duplicate()
	var derived := Surface.new()
	check(derived.build(base, size, water.source_hash, water).is_empty(), "Derived ground builds.")
	check(base == original and water.mask_bytes == mask and water.surface_levels == levels, "Both input layers remain unchanged.")
	check(derived.modified_pixels > 0 and derived.heights != base, "Derived ground physically differs from source.")
	var bed_ok := true
	var bank_ok := true
	for i in range(base.size()):
		if levels[i] >= 0:
			bed_ok = bed_ok and derived.heights[i] < levels[i]
			var x := i % size.x
			for next in [i - 1 if x > 0 else -1, i + 1 if x < size.x - 1 else -1, i - size.x, i + size.x]:
				if next >= 0 and next < base.size() and levels[next] < 0 and base[next] >= 0.2:
					bank_ok = bank_ok and derived.heights[next] >= levels[i]
	check(bed_ok and bank_ok, "Beds are submerged and adjoining dry land contains water.")
	check(derived.heights[0] == base[0], "Distant terrain remains unchanged.")
	var repeat := Surface.new()
	repeat.build(base, size, water.source_hash, water)
	check(repeat.heights == derived.heights, "Surface conditioning is deterministic.")
	var restored := Surface.decode(JSON.parse_string(JSON.stringify(derived.snapshot())))
	check(restored.error.is_empty() and restored.layer.heights == derived.heights, "Surface floats survive JSON losslessly.")
	var water_disk := Water.decode(JSON.parse_string(JSON.stringify(water.snapshot())))
	check(water_disk.error.is_empty() and water_disk.layer.hydraulic_fingerprint() == water.hydraulic_fingerprint(), "Hydraulic profiles and source identity survive JSON.")
	if not water.river_features.is_empty():
		water.river_features[0].name = "Test River"
		check(Water.decode(water.snapshot()).layer.river_features[0].name == "Test River", "Named water features persist independently of ground.")
	if not water.river_features.is_empty():
		var corrupt_water := water.snapshot()
		var p: PackedFloat32Array = water.river_features[0].profile.duplicate()
		p[7] = minf(1, p[3] + 0.01)
		corrupt_water.river_features[0].profile = preload("res://scripts/storage/float_payload.gd").encode(p)
		check(not Water.decode(corrupt_water).error.is_empty(), "Imported uphill river profiles are rejected.")
	var legacy := water.snapshot()
	legacy.version = 1
	for key in ["surface_levels", "river_features", "lake_features"]:
		legacy.erase(key)
	var old_water := Water.decode(legacy)
	check(old_water.error.is_empty() and not derived.build(base, size, water.source_hash, old_water.layer).is_empty(), "Old water remains readable and requires explicit regeneration for ground builds.")
	check(restored.layer.validate_water(old_water.layer).is_empty(), "Legacy artwork cannot activate or index a hydraulic surface cache.")
	var corrupt: Dictionary = restored.layer.snapshot()
	corrupt.heights.count += 1
	check(not Surface.decode(corrupt).error.is_empty(), "Corrupt surface payloads are rejected.")
	var old_manifest := Manifest.capture(Manifest._legacy_layers(), "old.terrain.json", "heightmap")
	old_manifest.version = 1
	old_manifest.layers.remove_at(3)
	old_manifest.layers.remove_at(2)
	old_manifest.layers[0].locked = true
	var file := FileAccess.open("res://.test-runtime/terrain_surface_smoke-legacy.world.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(old_manifest))
	file.close()
	var bytes := FileAccess.get_file_as_bytes("res://.test-runtime/terrain_surface_smoke-legacy.world.json")
	var migrated := Manifest.load_file("res://.test-runtime/terrain_surface_smoke-legacy.world.json")
	check(migrated.error.is_empty() and migrated.document.layers.size() == 6 and migrated.document.layers[0].locked and bytes == FileAccess.get_file_as_bytes("res://.test-runtime/terrain_surface_smoke-legacy.world.json"), "Old manifest gains surface state in memory without rewriting old saves.")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	editor._controls.heightmap_resolution.value = 256
	editor.apply_settings()
	await editor.generate_water_layer()
	editor.play_map()
	check(editor._gameplay_map == null and editor.selected_layer == "surface", "Play explains the missing third step.")
	var source: PackedFloat32Array = terrain.map_renderer.normalized_heights.duplicate()
	await editor.build_terrain_surface()
	check(terrain.terrain_surface_current() and terrain.map_renderer.rendered_heights == terrain.terrain_surface.heights and terrain.map_renderer.normalized_heights == source, "Shared renderer displays derived data and retains canonical inputs.")
	var finished: PackedFloat32Array = terrain.terrain_surface.heights.duplicate()
	var doc := Document.capture(terrain)
	var bad_doc := doc.duplicate(true)
	var exposed := finished.duplicate()
	for i in range(exposed.size()):
		if terrain.water_layer.surface_levels[i] >= 0:
			exposed[i] = 1
			break
	bad_doc.terrain_surface.heights = preload("res://scripts/storage/float_payload.gd").encode(exposed)
	check(not Document.apply(terrain, bad_doc).is_empty() and terrain.terrain_surface.heights == finished, "Exposed beds are rejected before modifying the live document.")
	check(Document.validate(doc).is_empty() and Document.apply(terrain, doc).is_empty() and terrain.terrain_surface.heights == finished and terrain.terrain_surface_current(), "Document restores all three layers exactly.")
	editor.play_map()
	await process_frame
	check(editor._gameplay_map != null and editor._gameplay_map.get_node("Terrain").map_renderer.rendered_heights == finished, "Gameplay displays exact derived surface.")
	editor._return_from_map()
	await process_frame
	editor._layer_buttons.surface[0].button_pressed = false
	check(terrain.map_renderer.rendered_heights == source, "Surface visibility reveals original terrain.")
	editor._layer_buttons.surface[0].button_pressed = true
	editor._layer_buttons.surface[1].button_pressed = true
	check(not editor.regeneration_error("heightmap").is_empty() and not editor.regeneration_error("rivers").is_empty() and not editor.regeneration_error("surface").is_empty(), "Surface lock protects both upstream dependencies.")
	editor._layer_buttons.surface[1].button_pressed = false
	var retained = terrain.terrain_surface
	editor._controls.map_seed.text = "surface-stale"
	editor.apply_settings()
	check(terrain.terrain_surface == retained and not terrain.terrain_surface_current() and terrain.map_renderer.rendered_heights == terrain.map_renderer.normalized_heights, "Changed source retains but hides derived cache.")
	await editor.generate_water_layer()
	editor.build_terrain_surface()
	await process_frame
	check(editor._surface_busy, "Surface build runs in a background worker.")
	editor._water_job_serial += 1
	while editor._surface_busy:
		await process_frame
	check(terrain.terrain_surface == retained, "Replaced editing session rejects a pending surface result.")
	if DisplayServer.get_name() != "headless":
		editor._controls.heightmap_resolution.value = 1025
		editor._controls.map_seed.text = "42"
		editor.apply_settings()
		await editor.generate_water_layer()
		await editor.build_terrain_surface()
		check(terrain.terrain_surface_current(), "Rendered full-detail surface builds.")
		editor._select_layer("surface")
		await process_frame
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("SURFACE_OUTPUT")
		if not output.is_empty():
			root.get_texture().get_image().save_png(output.path_join("terrain-surface-workspace.png"))
			terrain.terrain_surface.export_image().save_png(output.path_join("terrain-surface-heightmap.png"))
		editor.play_map()
		await process_frame
		await RenderingServer.frame_post_draw
		check(editor._gameplay_map.get_node("Terrain").map_renderer.rendered_heights == terrain.terrain_surface.heights, "GPU gameplay uses the full-detail derived field.")
		if not output.is_empty():
			root.get_texture().get_image().save_png(output.path_join("terrain-surface-gameplay.png"))
		editor._return_from_map()
		await process_frame
	editor.build_terrain_surface()
	await process_frame
	world.queue_free()
	await process_frame
	print("Terrain surface: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
