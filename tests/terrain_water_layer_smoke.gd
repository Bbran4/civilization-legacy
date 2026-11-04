extends SceneTree
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
func _run() -> void:
	var size := Vector2i(129, 97)
	var heights := PackedFloat32Array()
	heights.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			var uv := Vector2(x, y) / Vector2(size - Vector2i.ONE)
			var basin := exp(-pow((uv.x - 0.5) / 0.12, 2) - pow((uv.y - 0.45) / 0.12, 2)) * 0.28
			heights[y * size.x + x] = 0.85 - uv.y * 0.8 + sin(uv.x * 18) * 0.015 - basin
	var before := heights.duplicate()
	var choices: Dictionary = Water.DEFAULTS.duplicate()
	choices.routing_resolution = 257
	choices.lake_area = 0.005
	var layer := Water.new()
	check(layer.generate(heights, size, "a".repeat(64), choices).is_empty(), "Synthetic drainage generates.")
	check(layer.river_reaches > 0 and layer.lake_count > 0, "A sloped basin produces both rivers and a real lake.")
	check(heights == before, "Water generation never changes source heights.")
	for i in range(layer.bed.size()):
		var next: int = layer.downstream[i]
		if next >= 0:
			check(layer.filled[next] <= layer.filled[i] + 0.000001, "Water flows downhill across the routing surface.")
	var rank := PackedInt32Array()
	rank.resize(layer.bed.size())
	rank.fill(-1)
	for j in range(layer._order.size()):
		rank[layer._order[j]] = j
	var exported := 0.0
	for i in layer._order:
		var next: int = layer.downstream[i]
		check(next < 0 or layer.ocean[next] != 0 or rank[next] < rank[i], "Drainage paths cannot contain cycles.")
		if next < 0 or layer.ocean[next] != 0:
			exported += layer.flow[i]
	check(absf(exported - layer._order.size()) < 0.001, "Uniform runoff is conserved through boundary and sea outlets.")
	var second := Water.new()
	second.generate(heights, size, "a".repeat(64), choices)
	check(second.mask_bytes == layer.mask_bytes, "Water generation is deterministic.")
	var decoded := Water.decode(layer.snapshot())
	check(decoded.error.is_empty() and decoded.layer.mask_bytes == layer.mask_bytes, "Water artwork restores losslessly.")
	check(layer._river_width(10000, 10) > layer._river_width(10, 10), "River width increases downstream with discharge.")
	check(layer.export_image().get_pixel(0, 0).a == 0.0, "Water PNG keeps unpainted areas transparent.")
	var invalid := layer.snapshot()
	invalid.size[0] = 900000
	check(not Water.decode(invalid).error.is_empty(), "Oversized water images are rejected before decoding.")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	check(editor._controls.heightmap_resolution.min_value == 256 and editor._controls.heightmap_resolution.max_value == 2050, "Output resolution exposes exact requested pixel bounds.")
	editor._controls.heightmap_resolution.value = 256
	editor.apply_settings()
	check(terrain.sample_size().x == 256 and terrain.resolution == 255, "Minimum output is exactly 256 pixels, not 257.")
	var original: PackedFloat32Array = terrain.height_samples.duplicate()
	var height_texture = terrain.map_renderer.material.get_shader_parameter("height_field")
	editor._select_layer("rivers")
	editor._layer_buttons.heightmap[1].button_pressed = true
	editor._water_controls.routing_resolution.select(0)
	await editor.generate_water_layer()
	check(terrain.water_layer_current() and terrain.height_samples == original, "Independent water generation works on a locked heightmap without changing it.")
	check(terrain.map_renderer.material.get_shader_parameter("height_field") == height_texture and terrain.map_renderer.material.get_shader_parameter("water_enabled"), "Overlay adds water without replacing the shared height texture.")
	editor._layer_buttons.heightmap[0].button_pressed = false
	check(terrain.visible and not terrain.map_renderer.material.get_shader_parameter("height_enabled") and terrain.map_renderer.material.get_shader_parameter("water_enabled"), "Water can be inspected alone with the height layer hidden.")
	editor._layer_buttons.heightmap[0].button_pressed = true
	editor._layer_buttons.rivers[0].button_pressed = false
	check(not terrain.map_renderer.material.get_shader_parameter("water_enabled"), "Water visibility hides only its overlay.")
	editor._layer_buttons.rivers[0].button_pressed = true
	var saved := Document.capture(terrain)
	check(Document.validate(saved).is_empty(), "Water-bearing terrain document validates.")
	check(Document.save_file("res://.test-runtime/terrain_water_layer_smoke-water-roundtrip.terrain.json", terrain).is_empty(), "Water artwork saves to disk.")
	var disk := Document.load_file("res://.test-runtime/terrain_water_layer_smoke-water-roundtrip.terrain.json")
	check(disk.ok, "JSON numeric settings validate after parsing a saved water document.")
	var mask: PackedByteArray = terrain.water_layer.mask_bytes.duplicate()
	check(Document.apply(terrain, saved).is_empty() and terrain.water_layer_current() and terrain.water_layer.mask_bytes == mask, "Save/load restores exact water and height data.")
	await editor.build_terrain_surface()
	check(terrain.terrain_surface_current(), "Derived surface builds before play.")
	editor.play_map()
	await process_frame
	check(editor._gameplay_map.get_node("Terrain").water_layer_current() and editor._gameplay_map.get_node("Terrain").map_renderer.material.get_shader_parameter("water_enabled") and editor._gameplay_map.get_node("Terrain").water_layer.mask_bytes == mask, "Gameplay receives the same independent water overlay.")
	editor._return_from_map()
	await process_frame
	editor._layer_buttons.heightmap[1].button_pressed = false
	editor._layer_buttons.rivers[1].button_pressed = true
	var protected_water = terrain.water_layer
	await editor.generate_water_layer()
	check(terrain.water_layer == protected_water, "Water lock blocks direct water regeneration.")
	editor._controls.map_seed.text = "water-changed"
	editor.apply_settings()
	check(terrain.height_samples == original, "Water lock protects its height dependency.")
	editor._layer_buttons.rivers[1].button_pressed = false
	editor.apply_settings()
	check(not terrain.water_layer_current() and terrain.water_layer.mask_bytes == mask and not terrain.map_renderer.material.get_shader_parameter("water_enabled"), "Changed heights retain the old water artwork as stale and hide it.")
	check(editor._water_status.text.contains("Heightmap changed"), "Stale water is explained in the layer panel.")
	if DisplayServer.get_name() != "headless":
		# Restore a full-detail map for an actual renderer inspection, not a benchmark.
		editor._controls.heightmap_resolution.value = 1025
		editor._controls.map_seed.text = "42"
		editor.apply_settings()
		editor._select_layer("rivers")
		editor._water_controls.routing_resolution.select(1)
		await editor.generate_water_layer()
		await process_frame
		await RenderingServer.frame_post_draw
		var visible_image := root.get_texture().get_image()
		visible_image.save_png("res://.godot/water-layer-workspace.png")
		editor._layer_buttons.rivers[0].button_pressed = false
		await process_frame
		await RenderingServer.frame_post_draw
		var hidden_image := root.get_texture().get_image()
		var blue := 0
		var hidden_blue := 0
		for y in range(210, 590, 3):
			for x in range(315, 835, 3):
				var a := visible_image.get_pixel(x, y)
				var b := hidden_image.get_pixel(x, y)
				blue += 1 if a.b - a.r > 0.05 else 0
				hidden_blue += 1 if b.b - b.r > 0.05 else 0
		check(blue > 30 and hidden_blue == 0, "GPU water overlay is visible and hides independently of grayscale terrain.")
		editor._layer_buttons.rivers[0].button_pressed = true
		terrain.water_layer.export_image().save_png("res://.godot/water-layer.png")
	editor.generate_water_layer()
	await process_frame
	check(editor._water_busy, "A background worker may be active when closing the editor.")
	world.queue_free()
	await process_frame
	print("Independent water layer: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
