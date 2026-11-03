extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var layer := Provinces.new()
	layer.size = Vector2i(129, 97)
	layer.source_hash = "a".repeat(64)
	layer.ids.resize(129 * 97)
	var base := PackedFloat32Array()
	base.resize(layer.ids.size())
	base.fill(0.1)
	for y in range(25, 71):
		for x in range(45, 86):
			layer.ids[y * 129 + x] = 1
			base[y * 129 + x] = 0.6
	var water := Water.new()
	water.mask_size = layer.size
	water.mask_bytes.resize(base.size() * 4)
	var lake := 45 * 129 + 60
	water.mask_bytes[lake * 4 + 1] = 255
	layer.ids[lake] = 0
	var inland := 50 * 129 + 70
	base[inland] = 0.1
	layer.ids[inland] = 0
	layer.records.append({"id":1,"kind":"land","name":"Mainland"})
	layer._index_regions()
	var original := layer.ids.duplicate()
	check(layer.generate_oceans(base, water, 12, "coastal_band", 64).is_empty(), "Finite coastal seas generate.")
	var classes := Provinces.classify(base, 0.2, water.mask_bytes, layer.size)
	var band := Provinces.coastal_band(classes, layer.size, 64)
	var valid := true
	var deep := 0
	var coastal := 0
	for i in range(layer.ids.size()):
		if original[i] == 1: valid = valid and layer.ids[i] == 1
		elif band[i] != 0:
			coastal += 1
			valid = valid and layer.ids[i] > 1
		elif classes[i] == 2:
			deep += 1
			valid = valid and layer.ids[i] == 0 and layer.sea_mask[i] == 1
	check(valid and deep > 1000 and coastal > 100, "Coastal IDs stop at the sea band and deep ocean remains unassigned.")
	check(layer.ids[lake] == 0 and layer.ids[inland] == 0 and layer.sea_mask[lake] == 0 and layer.sea_mask[inland] == 0, "Lakes and inland water stay unassigned and are not deep-ocean background.")
	check(layer.validate_coverage(base, 0.2, water).is_empty(), "Coverage validates both coastal zones and borderless sea.")
	var texture: Image = layer.texture().get_image()
	check(texture.get_pixel(0, 0).r == 0 and texture.get_pixel(0, 0).g == 0 and absf(texture.get_pixel(0, 0).b - 2.0 / 255) < 0.00001, "Deep water texture carries background classification but no province ID.")
	var restored := Provinces.decode(JSON.parse_string(JSON.stringify(layer.snapshot())))
	check(restored.error.is_empty() and restored.layer.ids == layer.ids and restored.layer.sea_mask == layer.sea_mask and restored.layer.coastal_reach == 64, "Coastal IDs, background mask and reach restore exactly through JSON.")
	var copy: RefCounted = layer.editable_copy()
	copy.sea_mask[0] = 0
	check(layer.sea_mask[0] == 1, "Draft mask changes cannot mutate the installed sea background.")
	copy = layer.editable_copy()
	copy.generate_oceans(base, water, 12, "coastal_band", 128)
	var wider := 0
	for i in range(copy.ids.size()):
		if copy.ids[i] > 1: wider += 1
	check(wider > coastal, "Coastal reach changes zone extent rather than partitioning the whole ocean.")
	var legacy_regions: RefCounted = layer.editable_copy()
	legacy_regions.generate_oceans(base, water, 6, "coastal")
	var legacy_data: Dictionary = legacy_regions.snapshot()
	legacy_data.version = 3
	legacy_data.erase("sea_mask")
	legacy_data.erase("coastal_reach")
	var legacy_restore := Provinces.decode(legacy_data)
	check(legacy_restore.error.is_empty() and legacy_restore.layer.ids == legacy_regions.ids and legacy_restore.layer.ocean_style == "coastal", "Older full-ocean v3 maps restore without silently changing their IDs.")
	var invalid: Dictionary = layer.snapshot()
	invalid.coastal_reach = 0
	check(not Provinces.decode(invalid).error.is_empty(), "Invalid coastal reach is rejected.")
	copy = layer.editable_copy()
	copy.sea_mask[lake] = 1
	check(not copy.validate_coverage(base, 0.2, water).is_empty(), "Lake pixels cannot be reclassified as open ocean.")
	var empty := Provinces.new()
	empty.size = Vector2i(17, 17)
	empty.source_hash = "b".repeat(64)
	empty.ids.resize(17 * 17)
	var flat := PackedFloat32Array()
	flat.resize(empty.ids.size())
	flat.fill(0.1)
	var sea := Water.new()
	sea.mask_size = empty.size
	sea.mask_bytes.resize(flat.size() * 4)
	check(empty.generate_oceans(flat, sea, 4).is_empty() and empty.records.is_empty() and empty.validate_coverage(flat, 0.2, sea).is_empty(), "A coastless map remains one continuous unassigned ocean background.")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	world.get_node("Terrain").resolution = 255 if DisplayServer.get_name() == "headless" else 1024
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	await editor.generate_water_layer()
	await editor.build_terrain_surface()
	editor._select_layer("provinces")
	await editor.generate_provinces()
	var land_ids: PackedInt32Array = terrain.province_layer.ids.duplicate()
	await editor.generate_ocean_borders()
	check(terrain.province_layer.ocean_style == "coastal_band" and terrain.province_layer.coastal_reach == 64, "Editor defaults generate the reference-style coastal band.")
	var kept := true
	for i in range(land_ids.size()):
		if land_ids[i] > 0: kept = kept and land_ids[i] == terrain.province_layer.ids[i]
	check(kept, "Coastal ocean rebuild preserves all authored land IDs.")
	check(Document.save_file("user://coastal-seas.terrain.json", terrain).is_empty(), "Coastal maps save to disk.")
	var disk := Document.load_file("user://coastal-seas.terrain.json")
	check(disk.ok and Document.apply(terrain, disk.document).is_empty() and terrain.province_layer.ocean_style == "coastal_band", "Full map restores coastal/open-water data without regeneration.")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var output := OS.get_environment("COASTAL_OUTPUT")
		if not output.is_empty(): root.get_texture().get_image().save_png(output.path_join("coastal-seas-workspace.png"))
		editor.play_map()
		await process_frame
		var player = editor._gameplay_map.get_node("Terrain")
		var toggle: CheckButton
		for child in editor._gameplay_map.get_node("MapHUD").get_child(0).get_children():
			if child is CheckButton: toggle = child
		toggle.button_pressed = true
		await RenderingServer.frame_post_draw
		check(player.province_layer.ids == terrain.province_layer.ids and player.province_layer.sea_mask == terrain.province_layer.sea_mask, "Gameplay uses identical coastal zones and borderless open-ocean mask.")
		var image := root.get_texture().get_image()
		if not output.is_empty(): image.save_png(output.path_join("coastal-seas-gameplay.png"))
		# Project actual raster samples into the GPU capture to verify the two sea colors.
		var camera: Camera3D = editor._gameplay_map.get_node("CameraRig/Camera3D")
		var blue := 0
		var dark := 0
		var dimensions: Vector2i = player.province_layer.size
		for y in range(3, dimensions.y - 3, 7):
			for x in range(3, dimensions.x - 3, 7):
				var i := y * dimensions.x + x
				if player.province_layer.sea_mask[i] == 0: continue
				var local: Vector2 = (Vector2(x, y) / Vector2(dimensions - Vector2i.ONE) - Vector2.ONE * 0.5) * player.display_size()
				var screen := Vector2i(camera.unproject_position(player.to_global(Vector3(local.x, 0, local.y))))
				if screen.x < 0 or screen.y < 50 or screen.x >= image.get_width() or screen.y >= image.get_height(): continue
				var c := image.get_pixelv(screen)
				if player.province_layer.ids[i] == 0 and Vector3(c.r,c.g,c.b).distance_to(Vector3(0.16,0.21,0.27)) < 0.035: dark += 1
				if player.province_layer.ids[i] > 0 and Vector3(c.r,c.g,c.b).distance_to(Vector3(0.27,0.42,0.61)) < 0.035: blue += 1
		check(blue > 20 and dark > 20, "Actual GPU output has light coastal sea and uniform dark open ocean.")
		editor._return_from_map()
		await process_frame
	world.queue_free()
	await process_frame
	print("Coastal seas and borderless ocean: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
