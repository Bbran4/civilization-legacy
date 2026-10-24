extends SceneTree
## Production-scene checks: reproducibility, live edits, image input and bounds.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, explanation: String) -> void:
	if not condition:
		_failures += 1
		push_error(explanation)


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var world := scene.instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var surface := terrain.get_node("Surface") as MeshInstance3D
	_check(surface.mesh != null, "Main scene must generate a terrain mesh.")
	_check(terrain.height_samples.size() == terrain.sample_size().x * terrain.sample_size().y, "Default resolution must generate the expected grid.")
	terrain.template_detail = 0.05
	terrain.regenerate()
	var original: PackedFloat32Array = terrain.height_samples.duplicate()
	terrain.regenerate()
	_check(original == terrain.height_samples, "Identical settings must reproduce identical heights.")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		_check(screenshot.save_png("res://.godot/terrain-preview.png") == OK, "Preview image must save.")
	terrain.land_noise.seed += 1
	await create_timer(0.35).timeout
	_check(original != terrain.height_samples, "Editing a nested noise resource must trigger regeneration.")
	terrain.map_size = Vector2(192, 192)
	terrain.resolution = 16
	terrain.island_enabled = false
	terrain.height_contrast = 1.0
	terrain.elevation = 10.0
	terrain.height_offset = -2.0
	var image := Image.create(2, 2, false, Image.FORMAT_RF)
	image.fill(Color.WHITE)
	terrain.heightmap_texture = ImageTexture.create_from_image(image)
	terrain.image_blend = 1.0
	terrain.template_detail = 0.0
	terrain.mountain_strength = 0.0
	terrain.regenerate()
	_check(is_equal_approx(terrain.height_samples[0], 6.0), "White heightmap must reach the configured maximum height.")
	terrain.invert_image = true
	terrain.regenerate()
	_check(is_equal_approx(terrain.height_samples[0], -4.0), "Inverted white heightmap must reach the configured minimum height.")
	image.fill(Color.BLACK)
	image.set_pixel(1, 0, Color.WHITE)
	image.set_pixel(1, 1, Color.WHITE)
	terrain.heightmap_texture = ImageTexture.create_from_image(image)
	terrain.invert_image = false
	terrain.regenerate()
	_check(absf(terrain.base_surface_height(Vector2(0.5, 0.5)) / terrain.relief_scale() - 1.8) < 0.3, "Image heights must interpolate and follow the source generator’s precreated-image height curve.")
	terrain.show_water = false
	terrain.regenerate()
	_check(not terrain.get_node("Water").visible, "Water visibility setting must apply.")
	var packed := PackedScene.new()
	_check(packed.pack(world) == OK, "World scene must remain packable.")
	var saved := packed.instantiate()
	_check(saved.get_node("Terrain").get_child_count(true) == 0, "Generated meshes must not be saved into authored scenes.")
	saved.free()
	terrain.resolution = 10000
	terrain.regenerate()
	_check(terrain.height_samples.size() == 1025 * 1025, "Resolution must remain bounded for Inspector edits.")
	world.queue_free()
	await process_frame
	print("Terrain smoke checks: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
