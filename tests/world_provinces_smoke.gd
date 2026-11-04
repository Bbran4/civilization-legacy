extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Surface = preload("res://scripts/domain/terrain_surface.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
const Manifest = preload("res://scripts/storage/world_manifest.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var base := PackedFloat32Array()
	var size := Vector2i(65, 49)
	base.resize(size.x * size.y)
	base.fill(0.6)
	var water := Water.new()
	water.source_hash = "a".repeat(64)
	water.mask_size = size
	water.mask_bytes.resize(base.size() * 4)
	for y in range(size.y):
		for x in range(size.x):
			if x == 31 or x == 32: base[y * size.x + x] = 0.1
			if x >= 10 and x <= 14 and y >= 10 and y <= 14:
				water.mask_bytes[(y * size.x + x) * 4 + 1] = 255
	var surface := Surface.new()
	surface.size = size
	surface.source_hash = water.source_hash
	surface.water_hash = "b".repeat(64)
	surface.heights = base.duplicate()
	var before := base.duplicate()
	var provinces := Provinces.new()
	check(not provinces.generate(base, null, water, 8).is_empty() and not provinces.generate(base, surface, water, 0).is_empty(), "Missing and out-of-range generation inputs are rejected.")
	check(provinces.generate(base, surface, water, 8).is_empty(), "Synthetic connected provinces generate.")
	check(base == before and surface.heights == before, "Province authoring preserves terrain inputs.")
	var masked := true
	for i in range(base.size()):
		masked = masked and ((provinces.ids[i] == 0) == (base[i] < 0.2 or water.mask_bytes[i * 4 + 1] > 0))
	check(masked, "All land is assigned and sea/lake pixels remain unassigned.")
	var repeat := Provinces.new()
	repeat.generate(base, surface, water, 8)
	check(repeat.ids == provinces.ids, "Province generation is deterministic.")
	provinces.records[0].name = "North Reach"
	var restored := Provinces.decode(JSON.parse_string(JSON.stringify(provinces.snapshot())))
	check(restored.error.is_empty() and restored.layer.ids == provinces.ids and restored.layer.records == provinces.records, "IDs, names, areas and adjacency restore exactly.")
	var symmetric := true
	for record in provinces.records:
		for other in record.neighbors:
			symmetric = symmetric and record.id in provinces.records[other - 1].neighbors
	check(symmetric, "Adjacency is symmetric.")
	var invalid := provinces.snapshot()
	invalid.ids.count += 1
	check(not Provinces.decode(invalid).error.is_empty(), "Invalid province raster dimensions are rejected.")
	# A province cannot own two disconnected pieces of land.
	var disconnected := Provinces.new()
	disconnected.size = Vector2i(3, 3)
	disconnected.source_hash = "c".repeat(64)
	disconnected.ids = PackedInt32Array([1,2,2,2,2,2,2,2,1])
	disconnected.records.append({"id":1,"name":"Broken","active":true})
	disconnected.records.append({"id":2,"name":"Surrounding","active":true})
	check(not Provinces.decode(disconnected.snapshot()).error.is_empty(), "Imported disconnected province identities are rejected.")
	var layers := Manifest._legacy_layers()
	var old := Manifest.capture(layers, "map.terrain.json", "surface")
	old.version = 2
	old.layers.remove_at(3)
	var file := FileAccess.open("res://.test-runtime/world_provinces_smoke-v2.world.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var bytes := FileAccess.get_file_as_bytes("res://.test-runtime/world_provinces_smoke-v2.world.json")
	var migration := Manifest.load_file("res://.test-runtime/world_provinces_smoke-v2.world.json")
	check(migration.error.is_empty() and migration.document.layers.size() == 5 and bytes == FileAccess.get_file_as_bytes("res://.test-runtime/world_provinces_smoke-v2.world.json"), "V2 manifests migrate without rewriting prior files.")
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
	await editor.generate_provinces()
	check(terrain.province_layer == null, "Provinces require the finished surface.")
	if DisplayServer.get_name() != "headless":
		editor._controls.heightmap_resolution.value = 1025
		editor.apply_settings()
	await editor.generate_water_layer()
	await editor.build_terrain_surface()
	editor._select_layer("provinces")
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var ground: PackedFloat32Array = terrain.terrain_surface.heights.duplicate()
	await editor.generate_provinces()
	check(terrain.province_layer_current() and terrain.height_samples == heights and terrain.terrain_surface.heights == ground, "Integrated provinces preserve all terrain inputs.")
	check(terrain.map_renderer.material.get_shader_parameter("provinces_enabled"), "Province overlay is enabled in the editor.")
	editor._select_province(1)
	var nation: int = terrain.province_layer.add_nation("Test realm",Color(0.7,0.1,0.08))
	editor._sync_nation_choices()
	editor._province_nation.select(nation)
	editor._assign_province_nation()
	check(terrain.province_layer.records[0].nation_id == nation,"Editor assigns a nation to the selected land province.")
	editor._province_name.text = "Saved Province"
	editor.rename_province()
	var saved := Document.capture(terrain)
	check(Document.save_file("res://.test-runtime/world_provinces_smoke-province-roundtrip.terrain.json", terrain).is_empty(), "Province terrain document saves to disk.")
	var disk := Document.load_file("res://.test-runtime/world_provinces_smoke-province-roundtrip.terrain.json")
	check(disk.ok and Document.apply(terrain, disk.document).is_empty(), "Province document restores from actual JSON disk data.")
	check(terrain.province_layer.records[0].nation_id == nation and terrain.province_layer.nations.size() == 1,"Nation assignments and palette restore through full terrain saves.")
	var bad := saved.duplicate(true)
	var payload := preload("res://scripts/storage/float_payload.gd").decode(bad.province_layer.ids, terrain.height_samples.size(), 0, terrain.province_layer.records.size())
	for i in range(payload.values.size()):
		if payload.values[i] > 0:
			payload.values[i] = 0
			break
	bad.province_layer.ids = preload("res://scripts/storage/float_payload.gd").encode(payload.values)
	check(not Document.apply(terrain, bad).is_empty(), "Incomplete current land coverage is rejected before application.")
	check(Document.validate(saved).is_empty() and Document.apply(terrain, saved).is_empty() and terrain.province_layer.records[0].name == "Saved Province", "Province names and identity round-trip through terrain documents.")
	editor._layer_buttons.provinces[0].button_pressed = false
	check(not terrain.map_renderer.material.get_shader_parameter("provinces_enabled"), "Province visibility changes only presentation.")
	editor._layer_buttons.provinces[0].button_pressed = true
	editor._layer_buttons.provinces[1].button_pressed = true
	check(not editor.regeneration_error("heightmap").is_empty() and not editor.regeneration_error("rivers").is_empty() and not editor.regeneration_error("surface").is_empty(), "Province lock protects every upstream input.")
	editor._province_nation.select(0)
	editor._assign_province_nation()
	check(terrain.province_layer.records[0].nation_id == nation,"Province lock prevents nation reassignment.")
	editor._province_name.text = "Blocked"
	editor.rename_province()
	check(terrain.province_layer.records[0].name == "Saved Province", "Locked province names cannot change.")
	editor._layer_buttons.provinces[1].button_pressed = false
	editor._select_province(1)
	editor.play_map()
	await process_frame
	check(editor._gameplay_map.get_node("Terrain").province_layer_current(), "Gameplay receives exact province data.")
	var player_terrain = editor._gameplay_map.get_node("Terrain")
	check(not player_terrain.map_renderer.material.get_shader_parameter("provinces_enabled"), "Gameplay starts with the terrain view.")
	player_terrain.set_province_layer_visible(true)
	check(player_terrain.map_renderer.material.get_shader_parameter("provinces_enabled"), "Gameplay can enable political inspection.")
	editor._return_from_map()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("PROVINCE_OUTPUT")
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("province-workspace.png"))
	var retained = terrain.province_layer
	editor.generate_provinces()
	await process_frame
	editor._water_job_serial += 1
	while editor._province_busy: await process_frame
	check(terrain.province_layer == retained, "Changed document session rejects pending provinces.")
	editor._controls.map_seed.text = "changed-province-source"
	editor.apply_settings()
	check(terrain.province_layer == retained and not terrain.province_layer_current() and not terrain.map_renderer.material.get_shader_parameter("provinces_enabled"), "Changed terrain retains but hides old provinces.")
	check(Document.validate(Document.capture(terrain)).is_empty(), "Stale province data remains safely saveable after source changes.")
	await editor.generate_water_layer()
	await editor.build_terrain_surface()
	editor.generate_provinces()
	await process_frame
	world.queue_free()
	await process_frame
	print("World provinces: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
