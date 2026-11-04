extends SceneTree
const Document = preload("res://scripts/storage/terrain_document.gd")
const Manifest = preload("res://scripts/storage/world_manifest.gd")
const Graph = preload("res://scripts/domain/map_layer_graph.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	_run.call_deferred()
func _run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	terrain.map_size = Vector2(192,144)
	terrain.resolution = 128
	terrain.graph_points = 1000
	terrain.regenerate()
	var Water = load("res://scripts/domain/terrain_water_layer.gd")
	var Surface = load("res://scripts/domain/terrain_surface.gd")
	var Provinces = load("res://scripts/domain/world_provinces.gd")
	var water = Water.new()
	check(water.generate(terrain.map_renderer.normalized_heights,terrain.sample_size(),terrain.water_source_hash,Water.DEFAULTS).is_empty(),"Generate water")
	terrain.install_water_layer(water)
	var surface = Surface.new()
	check(surface.build(terrain.map_renderer.normalized_heights,terrain.sample_size(),terrain.water_source_hash,water).is_empty(),"Build surface")
	terrain.install_terrain_surface(surface)
	var provinces = Provinces.new()
	check(provinces.generate(terrain.map_renderer.normalized_heights,surface,water,16).is_empty(),"Generate provinces")
	terrain.install_province_layer(provinces)
	terrain.set_province_fill(false)
	editor._sync_from_terrain()
	editor._select_layer("paint")
	check(editor.layers.size() == 6 and editor.layers[1].id == "paint", "Paint is a separate layer above heightmap")
	check(Graph.affected(editor.layers,"paint") == ["paint","trees"], "Ground appearance can affect trees without invalidating geography")
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var fingerprint: String = terrain.water_source_hash
	var brush = editor._paint_brush
	brush.enabled.button_pressed = true
	var camera: Camera3D = editor._camera_rig.get_node("Camera3D")
	var screen := camera.unproject_position(Vector3.ZERO)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen
	check(brush.handle_input(down), "Paint input consumed by selected brush")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	check(brush.handle_input(up), "Release ends stroke")
	check(terrain.map_paint.image.get_pixel(512,512).a > 0, "Brush hits the displayed overview plane")
	check(terrain.water_layer == water and terrain.terrain_surface == surface and terrain.province_layer == provinces,"Paint preserves derived layer instances")
	check(terrain.height_samples == heights and terrain.water_source_hash == fingerprint,"Paint preserves generated geography")
	var path := "res://.test-runtime/map-paint.terrain.json"
	check(Document.save_file(path,terrain).is_empty(), "Paint saves inside terrain JSON")
	var loaded := Document.load_file(path)
	check(loaded.ok,"Paint document validates")
	brush.undo()
	check(terrain.map_paint.image.get_pixel(512,512).a == 0,"Undo restores transparent terrain")
	check(Document.apply(terrain,loaded.document).is_empty() and terrain.map_paint.image.get_pixel(512,512).a > 0,"Load restores paint")
	var painted: PackedByteArray = terrain.map_paint.image.get_data()
	editor._layer_buttons.paint[1].button_pressed = true
	check(not editor.can_edit("paint"),"Paint lock respected")
	brush.clear()
	check(terrain.map_paint.image.get_data() == painted,"Locked paint cannot clear")
	editor._layer_buttons.paint[1].button_pressed = false
	editor._layer_buttons.paint[0].button_pressed = false
	check(not terrain.map_renderer.material.get_shader_parameter("paint_enabled"),"Visibility affects only paint presentation")
	editor._layer_buttons.paint[0].button_pressed = true
	check(terrain.map_renderer.material.get_shader_parameter("paint_enabled"),"Paint visible again")
	terrain.regenerate()
	check(terrain.map_paint.image.get_data() == painted,"Regeneration preserves paint")
	var old: Dictionary = loaded.document.duplicate(true)
	old.version = 11
	old.erase("map_paint")
	check(Document.apply(terrain,old).is_empty() and terrain.map_paint.image.get_pixel(512,512).a == 0,"Older saves start with transparent paint")
	var missing: Dictionary = loaded.document.duplicate(true)
	missing.erase("map_paint")
	check(not Document.validate(missing).is_empty(),"Current saves cannot silently omit paint")
	var bad: Dictionary = loaded.document.duplicate(true)
	bad.map_paint = {"version":1,"png":"aW52YWxpZA=="}
	check(not Document.apply(terrain,bad).is_empty(),"Malformed paint rejected before application")
	check(editor.save_world("res://.test-runtime/map-paint.world.json").is_empty(),"World manifest includes paint layer")
	check(Manifest.load_file("res://.test-runtime/map-paint.world.json").document.layers.size() == 6,"Manifest retains paint visibility and lock state")
	check(editor.load_world("res://.test-runtime/map-paint.world.json").is_empty(),"World manifest reloads")
	var legacy := Manifest.capture(Manifest._layers_for_version(4),"map-paint.terrain.json","surface")
	legacy.version = 4
	var legacy_path := "res://.test-runtime/map-paint-v4.world.json"
	check(Manifest.save_file(legacy_path,legacy).is_empty(),"Legacy four-layer manifest fixture")
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
	var migrated := Manifest.load_file(legacy_path)
	check(migrated.error.is_empty() and migrated.document.layers.size() == 6 and migrated.document.layers[1].id == "paint" and FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes,"Legacy manifest gains paint without modifying source")
	if "--capture" in OS.get_cmdline_user_args() or "--capture3d" in OS.get_cmdline_user_args():
		editor._select_layer("paint")
		terrain.map_paint.begin_stroke()
		terrain.map_paint.stamp(Vector2(0.5,0.5),terrain.map_size,70,Color("718a52"))
		terrain.map_paint.refresh()
		if "--capture3d" in OS.get_cmdline_user_args():
			editor._camera_rig._zoom = 1.7
			editor._camera_rig._apply_zoom()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-runtime/map-paint-preview.png")
	world.free()
	print("Map paint smoke: %d failures" % failures)
	quit(1 if failures else 0)
