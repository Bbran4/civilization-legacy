extends SceneTree
const Detail = preload("res://scripts/domain/heightmap_detail.gd")
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var graph := Graph.new()
	graph.generate(Vector2(192, 144), 1000, "42")
	var size := Vector2i(129, 97)
	for preset in Recipe.PRESETS:
		Recipe.new().generate(graph, preset, "42")
		var cells := graph.heights.duplicate()
		var coarse := graph.rasterize(size, 1)
		var refined := Detail.refine(coarse, size, "42", 0.75, 0.8)
		check(refined == Detail.refine(coarse, size, "42", 0.75, 0.8), preset + " refinement is reproducible.")
		check(refined != coarse and refined != Detail.refine(coarse, size, "43", 0.75, 0.8), preset + " gains seeded detail.")
		check(graph.heights == cells and Detail.refine(coarse, size, "42", 0, 0) == coarse, "Template cells remain intact and zero settings preserve the base raster.")
		for h in refined:
			check(is_finite(h) and h >= 0 and h <= 1, "Refined heights remain finite and normalized.")
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	check(terrain.heightmap_only and terrain.heightmap_view and terrain.resolution == 1024 and terrain.effective_graph_points() == 20000, "Main scene opens in detailed heightmap focus.")
	check(terrain.climate == null and terrain.biomes == null and terrain.hydrology == null and terrain.vegetation_view == null and terrain.hydrology_view == null and terrain.provinces == null, "No climate, biomes, trees, rivers, lakes or province generators run.")
	check(terrain.detail == null and not terrain.get_node("Water").visible, "Heightmap uses one raster plane, with water and LOD relief disabled.")
	for layer in editor.layers:
		if layer.id not in ["heightmap", "rivers", "surface"]:
			check(not layer.visible and editor._layer_selectors[layer.id].disabled and not editor.can_edit(layer.id), "Other layers are visibly inactive and cannot be edited.")
	var image: Image = terrain.heightmap_image()
	check(image.get_size() == terrain.sample_size() and image.get_width() == 1025, "Export uses the detailed canonical sample grid.")
	for y in range(0, image.get_height(), 13):
		for x in range(0, image.get_width(), 13):
			var pixel := image.get_pixel(x, y)
			check(pixel.r == pixel.g and pixel.g == pixel.b, "Heightmap image is neutral grayscale.")
	var original: PackedFloat32Array = terrain.height_samples.duplicate()
	terrain.regenerate()
	check(terrain.height_samples == original, "Focused template generation is deterministic.")
	terrain.set_relief_preview(true)
	check(terrain.height_samples == original, "Relief preview never changes the height data.")
	terrain.set_relief_preview(false)
	var path := "user://heightmap-focus.terrain.json"
	check(Document.save_file(path, terrain).is_empty(), "Detailed heights remain compatible with terrain documents.")
	var loaded := Document.load_file(path)
	check(loaded.ok, "Detailed terrain document validates.")
	if loaded.ok:
		terrain.coast_detail = 0
		check(Document.apply(terrain, loaded.document).is_empty() and terrain.height_samples == original and terrain.coast_detail == 0.75, "Loading restores exact refined samples and detail choices without refining twice.")
		var old: Dictionary = loaded.document.duplicate(true)
		old.erase("heightmap_detail")
		check(Document.validate(old).is_empty(), "Prior terrain files remain readable without refinement metadata.")
		old.heightmap_detail = {"coast": "high", "mountains": 0.8}
		check(not Document.validate(old).is_empty(), "Invalid refinement metadata is rejected.")
	check(editor.save_world("user://heightmap-focus.world.json").is_empty(), "World Save All also supports the focused heightmap pipeline.")
	# Imported rasters bypass procedural embellishment: authored detail is not overwritten.
	var imported := Image.create(8, 8, false, Image.FORMAT_RF)
	for y in range(8):
		for x in range(8):
			imported.set_pixel(x, y, Color((float(x) * 0.8 + float(y) * 0.2) / 7.0, 0, 0))
	terrain.heightmap_texture = ImageTexture.create_from_image(imported)
	terrain.regenerate()
	var center: float = terrain.base_surface_height(Vector2(0.5, 0.5)) / terrain.relief_scale() / terrain.elevation + 0.2
	check(absf(center - 0.5) < 0.001, "Imported heights are sampled directly, without template noise or coarse-cell quantization.")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels := root.get_texture().get_image()
		var import_camera: Camera3D = world.get_node("CameraRig/Camera3D")
		var extent: Vector2 = terrain.display_size()
		var left := pixels.get_pixelv(Vector2i(import_camera.unproject_position(Vector3(-extent.x * 0.3, 0, 0))))
		var right := pixels.get_pixelv(Vector2i(import_camera.unproject_position(Vector3(extent.x * 0.3, 0, 0))))
		var top := pixels.get_pixelv(Vector2i(import_camera.unproject_position(Vector3(0, 0, -extent.y * 0.3))))
		var bottom := pixels.get_pixelv(Vector2i(import_camera.unproject_position(Vector3(0, 0, extent.y * 0.3))))
		check(right.r > left.r and bottom.r > top.r, "GPU heightmap orientation matches the canonical imported/exported raster.")
		check(right.r == right.g and right.g == right.b, "GPU preview is neutral grayscale.")
	if loaded.ok:
		Document.apply(terrain, loaded.document)
	var camera = world.get_node("CameraRig/Camera3D")
	var screen: Vector2 = camera.unproject_position(Vector3.ZERO)
	var hit: Variant = terrain.ray_surface_hit(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	check(hit != null and absf(hit.y) < 0.001, "Picking follows the flat raster preview plane.")
	var export_path := "res://.godot/heightmap-continents.png"
	check(terrain.heightmap_image().save_png(export_path) == OK, "Heightmap PNG export succeeds.")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/heightmap-workspace.png")
		terrain.set_relief_preview(true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/heightmap-relief-preview.png")
	world.queue_free()
	await process_frame
	print("Heightmap focus checks: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
