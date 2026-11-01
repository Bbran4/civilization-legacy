extends SceneTree
const Palette = preload("res://scripts/rendering/terrain_palette_library.gd")
const Catalog = preload("res://scripts/rendering/terrain_paint_catalog.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
const Sources = preload("res://scripts/rendering/terrain_materials.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _capture(name_text: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://.godot/palette-" + name_text + ".png")
	return image
func _solid(name_text: String, color: Color) -> String:
	var path: String = "res://.godot/paint-" + name_text + ".png"
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(color)
	image.save_png(path)
	return path
func _run() -> void:
	var defaults = load("res://assets/terrain/default_ground_palette.tres")
	_check(Catalog.validate_data(defaults.snapshot()).is_empty(), "All default biome and overlay rows must be valid editable assets.")
	var copy = defaults.duplicate(true)
	copy.rows[4].variants[0].amount = 0.1
	_check(defaults.rows[4].variants[0].amount == 1, "Runtime edits must not mutate the default asset or another map.")
	var world = load("res://scenes/main.tscn").instantiate()
	var terrain = world.get_node("Terrain")
	terrain.tree_population = 0
	root.add_child(world)
	await process_frame
	_check(terrain._paint_data.ok, "The actual renderer must create the biome palette.")
	if DisplayServer.get_name() != "headless":
		await _capture("natural-world")
	var source := Image.create(2, 2, false, Image.FORMAT_RF)
	source.fill(Color(0.32, 0, 0))
	terrain.heightmap_texture = ImageTexture.create_from_image(source)
	terrain.map_size = Vector2(128, 128)
	terrain.regenerate()
	var climate: Dictionary = terrain.climate_settings.duplicate()
	climate.latitude_center = 0
	climate.latitude_span = 10
	climate.temperature_bias = 20
	climate.rainfall_scale = 0
	_check(terrain.apply_climate(climate).is_empty(), "The dry palette fixture must apply valid climate settings.")
	var editor = world.get_node("Interface/Editor")
	editor._open_ground_palette()
	var panel = editor._material_panel
	panel._show_row(4)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var ui_image: Image = panel.get_texture().get_image()
		_check(ui_image != null and not ui_image.is_empty(), "The runtime texture panel must render its controls.")
		if ui_image != null:
			ui_image.save_png("res://.godot/palette-controls.png")
	_check(panel.cards.get_child_count() == 3, "The live editor must expose three independent texture slots per biome.")
	var red: String = _solid("red", Color(1, 0, 0, 0.2))
	var blue: String = _solid("blue", Color(0, 0, 1, 1))
	var green: String = _solid("green", Color(0, 1, 0, 1))
	var white: String = _solid("white", Color.WHITE)
	var mask := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var inverse := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var value: float = smoothstep(0.35, 0.65, Sources._noise(Vector2(x, y) / 64.0, Vector2i(4, 4), 51))
			mask.set_pixel(x, y, Color(value, value, value, 1))
			inverse.set_pixel(x, y, Color(1 - value, 1 - value, 1 - value, 1))
	mask.save_png("res://.godot/paint-mask.png")
	inverse.save_png("res://.godot/paint-inverse.png")
	panel._role = "albedo"
	panel._slot = 0
	panel._file_selected(red)
	_check(panel.catalog.rows[4].variants[0].albedo_path == red, "File selection must change the selected biome slot.")
	panel._set_value(12.0, "tile_size", 0)
	panel._set_value(37.0, "rotation", 0)
	for row in panel.catalog.rows:
		for slot in range(3):
			var v: Resource = row.variants[slot]
			v.albedo_path = red if slot == 0 else blue
			v.coverage_path = "res://.godot/paint-mask.png" if slot == 0 else "res://.godot/paint-inverse.png"
			v.amount = 1.0 if slot < 2 else 0.0
			v.patch_size = 24
	var painted: Resource = panel.catalog.rows[6].variants[0]
	painted.albedo_path = green
	painted.coverage_path = white
	panel.hide()
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var ids: PackedByteArray = terrain.biomes.ids.duplicate()
	var mesh: int = terrain.detail.chunks[0].meshes[0].get_instance_id()
	_check(await panel._apply(), "Apply textures must succeed through the live panel.")
	_check(terrain.height_samples == heights and terrain.biomes.ids == ids and terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh, "Applying a palette must not rebuild geometry or alter biome facts.")
	_check(terrain._land_material.get_shader_parameter("paint_albedo") == terrain.detail._material.get_shader_parameter("paint_albedo"), "All terrain LODs must share the same palette assets.")
	_check(terrain._paint_data.albedo.get_layers() == 57 and terrain._paint_data.normals.get_layers() == 57 and terrain._paint_data.coverage.get_layers() == 57, "Every biome/surface slot must have matching colour, normal and coverage layers.")
	var builds: int = Palette.build_count
	Palette.build(terrain.surface_catalog)
	_check(Palette.build_count == builds, "Rebinding an unchanged palette must reuse the cached texture arrays.")
	var invalid = terrain.surface_catalog.duplicate(true)
	for v in invalid.rows[4].variants:
		v.amount = 0
	var texture_id: int = terrain._paint_data.albedo.get_instance_id()
	_check(not terrain.apply_surface_catalog(invalid).is_empty() and terrain._paint_data.albedo.get_instance_id() == texture_id, "An empty biome mix must fail without replacing live textures.")
	var rig = world.get_node("CameraRig")
	rig._reset_view()
	if DisplayServer.get_name() != "headless":
		var before: Image = await _capture("red-blue")
		var red_count := 0
		var blue_count := 0
		for y in range(-14, 15, 2):
			for x in range(-14, 15, 2):
				var screen: Vector2 = rig._camera.unproject_position(Vector3(x, terrain.visible_surface_height(Vector2(0.5, 0.5)), y))
				var c: Color = before.get_pixelv(Vector2i(screen))
				_check(c.g < 0.015, "Red/blue albedo inputs must not acquire green from biome or pigment tinting.")
				red_count += int(c.r > c.b + 0.2)
				blue_count += int(c.b > c.r + 0.2)
		_check(red_count > 5 and blue_count > 5, "The custom mask must create visible patches of both source textures.")
	var brush = editor._brush
	brush.choose(6, 0)
	brush.radius.value = 8
	brush.strength.value = 1
	var center: Vector2 = terrain.map_size * 0.5
	var screen: Vector2 = rig._camera.unproject_position(Vector3(0, terrain.visible_surface_height(Vector2(0.5, 0.5)), 0))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = screen
	click.pressed = true
	editor._unhandled_input(click)
	_check(terrain.paint_layer.image != null, "A brush click through the real editor input handler must paint the ground.")
	brush._paint(center + Vector2(15, 0))
	click.pressed = false
	editor._unhandled_input(click)
	brush.enabled.button_pressed = false
	var image: Image = terrain.paint_layer.image
	var cell := Vector2i(Vector2(0.5, 0.5) * Vector2(image.get_size() - Vector2i.ONE))
	var value: Color = image.get_pixelv(cell)
	_check(roundi(value.r * 255) == 6 and roundi(value.b * 255) == 1 and value.g > 0.9, "Brush paint must retain its material row, chosen texture slot and strength.")
	if DisplayServer.get_name() != "headless":
		var after: Image = await _capture("green-brush")
		var c: Color = after.get_pixelv(Vector2i(screen))
		_check(c.g > 0.8 and c.r < 0.05 and c.b < 0.05, "The GPU must display the selected green texture at the painted point.")
	var inspected: Dictionary = terrain.point_info(center)
	_check(inspected.painted_ground == "Grassland" and inspected.biome != "Grassland", "Inspection must distinguish painted appearance from the native dry biome.")
	var document: Dictionary = Document.capture(terrain)
	_check(Document.validate(document).is_empty() and document.version == 10, "Current saves must include validated palette and paint data.")
	var png: String = document.ground_paint.png
	var undo_before: int = terrain.paint_layer.history.size()
	brush.undo()
	_check(terrain.paint_layer.image == null and undo_before == 1, "Undo must restore the empty layer for the entire drag stroke.")
	_check(Document.apply(terrain, document).is_empty() and terrain.paint_layer.snapshot().png == png and terrain.surface_catalog.snapshot() == document.ground_palette, "Saving and loading must restore exact paint pixels and all texture/pattern choices.")
	terrain.paint_layer.begin_stroke()
	terrain.paint_layer.stroke(center, center, 8, 1, 6, 0, true)
	var erased: Color = terrain.paint_layer.image.get_pixelv(cell)
	_check(erased.g < 0.01, "The eraser must uncover the generated biome material.")
	terrain.paint_layer.undo()
	_check(terrain.paint_layer.snapshot().png == png, "Undo must restore erased coverage exactly.")
	terrain.update_painted_surface()
	brush.clear()
	_check(terrain.paint_layer.image == null, "Clear ground paint must reveal the generated materials.")
	brush.undo()
	_check(terrain.paint_layer.snapshot().png == png, "Clearing paint must be undoable.")
	var bad: Dictionary = document.duplicate(true)
	bad.ground_palette.rows[4].variants[0].albedo_path = "res://.godot/missing-texture.png"
	var original_catalog: Resource = terrain.surface_catalog
	_check(not Document.apply(terrain, bad).is_empty() and terrain.surface_catalog == original_catalog and terrain.paint_layer.snapshot().png == png, "Missing image dependencies must fail before replacing the live map.")
	bad = document.duplicate(true)
	bad.ground_paint.png = "not a png"
	_check(not Document.apply(terrain, bad).is_empty() and terrain.paint_layer.snapshot().png == png, "Invalid painted ground must fail without modifying the world.")
	var old: Dictionary = document.duplicate(true)
	old.version = 9
	old.erase("ground_palette")
	old.erase("ground_paint")
	_check(Document.apply(terrain, old).is_empty() and terrain.paint_layer.image == null, "Older maps must gain the default material palette with no invented paint strokes.")
	_check(terrain.height_samples == heights and terrain.biomes.ids == ids, "Painting, undo, erase and loading must preserve source heights and biome IDs.")
	if DisplayServer.get_name() != "headless":
		brush.choose(6, -1)
		terrain.paint_layer.begin_stroke()
		brush.last_point = terrain.map_size * 0.5
		brush._paint(brush.last_point + Vector2(16, -8))
		brush.enabled.button_pressed = false
		editor._form.get_parent().get_v_scroll_bar().value = maxf(0, brush.enabled.position.y - 80)
		await _capture("brush-controls")
	world.queue_free()
	await process_frame
	print("Biome palette and painting checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

