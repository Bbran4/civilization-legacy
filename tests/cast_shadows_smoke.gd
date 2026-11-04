extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func capture() -> Image:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func rgb(color: Color) -> Vector3: return Vector3(color.r,color.g,color.b)
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cast shadows require GPU rendering; headless is not shadow verification.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	var world = load("res://scenes/main.tscn").instantiate()
	world.get_node("Terrain").resolution = 128
	world.get_node("Terrain").graph_points = 1000
	root.add_child(world)
	await process_frame
	world.get_node("Interface").visible = false
	var terrain = world.get_node("Terrain")
	var rig = world.get_node("CameraRig")
	var sun: DirectionalLight3D = world.get_node("Sun")
	terrain.map_size = Vector2(96,72)
	terrain.elevation = 60
	var tree_settings: Dictionary = terrain.tree_settings.duplicate()
	tree_settings.count = 0
	terrain.apply_tree_settings(tree_settings)
	var size = load("res://scripts/domain/heightmap_grid.gd").sample_size_for(terrain.map_size,128)
	var source := PackedFloat32Array()
	source.resize(size.x*size.y)
	for y in range(size.y):
		for x in range(size.x):
			var uv := Vector2(x,y)/Vector2(size-Vector2i.ONE)
			var ridge := maxf(0.0,1.0-absf(uv.x-0.42)/0.07)*maxf(0.0,1.0-absf(uv.y-0.5)/0.3)
			source[y*size.x+x] = (0.36+ridge*0.6-0.2)*60
	terrain.restore_heightfield(source,size)
	rig._reset_view()
	rig.max_zoom = 2048
	rig._pitch = 85
	rig._zoom = 3
	rig._apply_zoom()
	rig.position.y = terrain.visible_surface_height(Vector2(0.5,0.5))
	sun.rotation_degrees = Vector3(-35,-90,0)
	rig._fit_depth()
	var mountain_shadow := await capture()
	mountain_shadow.save_png("res://.test-runtime/mountain-shadows.png")
	terrain.map_renderer.surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mountain_clear := await capture()
	mountain_clear.save_png("res://.test-runtime/mountain-no-shadows.png")
	var mountain_pixels := 0
	for y in range(40):
		for x in range(40):
			# Known flat ground beyond the fixture ridge: slope shading cannot pass.
			var uv := Vector2(0.50+(x+0.5)*0.22/40.0,0.35+(y+0.5)*0.30/40.0)
			var point := Vector3((uv.x-0.5)*96,terrain.visible_surface_height(uv),(uv.y-0.5)*72)
			var pixel := Vector2i(rig._camera.unproject_position(point))
			if not Rect2i(Vector2i.ZERO,mountain_shadow.get_size()).has_point(pixel): continue
			if rgb(mountain_clear.get_pixelv(pixel)).length()-rgb(mountain_shadow.get_pixelv(pixel)).length() > 0.035: mountain_pixels += 1
	check(mountain_pixels > 100,"Mountains cast visible shadows onto separate flat ground")
	terrain.map_renderer.surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Actual generated tree instances, on a fresh flat source.
	source.fill((0.4-0.2)*60)
	terrain.restore_heightfield(source,size)
	tree_settings.count = 120
	tree_settings.coverage = 100
	terrain.apply_tree_settings(tree_settings)
	var forest = terrain.forest_view
	check(forest.positions.size() > 10,"Tree-shadow fixture has generated trees")
	if forest.positions.size() > 0:
		var uv: Vector2 = forest.positions[forest.positions.size()/2]
		rig.closest_view_size = 1
		rig._pitch = 65
		rig._zoom = rig._fit_size/10.0
		rig._apply_zoom()
		rig.position = Vector3((uv.x-0.5)*96,terrain.visible_surface_height(uv),(uv.y-0.5)*72)
		rig._fit_depth()
		var trees_shadow := await capture()
		trees_shadow.save_png("res://.test-runtime/tree-shadows.png")
		for child in forest.get_children(): child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var trees_clear := await capture()
		trees_clear.save_png("res://.test-runtime/tree-no-shadows.png")
		forest.hide()
		var bare := await capture()
		var tree_pixels := 0
		for y in range(trees_shadow.get_height()):
			for x in range(trees_shadow.get_width()):
				var no_cast := rgb(trees_clear.get_pixel(x,y))
				# Exclude leaves/trunks: require unchanged visible ground without trees.
				if no_cast.distance_to(rgb(bare.get_pixel(x,y))) > 0.01: continue
				if no_cast.length()-rgb(trees_shadow.get_pixel(x,y)).length() > 0.025: tree_pixels += 1
		check(tree_pixels > 80,"Trees cast shadows onto visible ground outside their silhouettes")
	world.free()
	print("Cast shadows: %d failures" % failures)
	quit(1 if failures else 0)
