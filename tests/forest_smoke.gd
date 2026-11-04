extends SceneTree
const Document = preload("res://scripts/storage/terrain_document.gd")
const Settings = preload("res://scripts/domain/forest_settings.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Manifest = preload("res://scripts/storage/world_manifest.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	_run.call_deferred()
func _check_clearance_cache() -> void:
	var surface := MeshInstance3D.new()
	root.add_child(surface)
	var renderer = load("res://scripts/rendering/terrain_map_renderer.gd").new(surface)
	var heights := PackedFloat32Array([0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5])
	renderer.set_heightfield(heights,Vector2i(3,3),Vector2(9,9),0,1,2)
	var water := Water.new()
	water.source_hash = "a".repeat(64)
	water.mask_size = Vector2i(3,3)
	water.mask_bytes.resize(36)
	renderer.set_water_layer(water,true)
	check(renderer.forest_site(Vector2(0.5,0.5),0.1).x > 0.25,"Dry footprint query")
	# Simulate the mask update/invalidation performed by the water producer.
	water.mask_bytes[4*4+1] = 255
	water._hydraulic_hash = ""
	renderer.set_water_layer(water,true)
	check(renderer.forest_site(Vector2(0.5,0.5),0.1).x < 0,"Mask-content changes invalidate clearance even on the same resource")
	renderer.set_water_layer(water,false)
	check(renderer.forest_site(Vector2(0.5,0.5),0.1).x < 0,"Hidden water still excludes trees")
	renderer.set_heightfield(heights,Vector2i(3,3),Vector2(9,9),0,1,2)
	check(renderer.forest_site(Vector2(0.5,0.5),0.1).x > 0.25,"New heightfield clears old mask binding")
	renderer.set_water_layer(water,true)
	check(renderer.forest_site(Vector2(0.5,0.5),0.1).x < 0,"Rebinding water after a source rebuild cannot reuse dry clearance")
	renderer = null
	surface.free()
func _run() -> void:
	_check_clearance_cache()
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	var rig = world.get_node("CameraRig")
	terrain.map_size = Vector2(96,72)
	terrain.resolution = 128
	terrain.graph_points = 1000
	terrain.elevation = 12
	terrain.regenerate()
	var size = load("res://scripts/domain/heightmap_grid.gd").sample_size_for(terrain.map_size,128)
	var source := PackedFloat32Array()
	source.resize(size.x*size.y)
	for y in range(size.y):
		for x in range(size.x):
			var uv := Vector2(x,y)/Vector2(size-Vector2i.ONE)
			var h := 0.44+uv.x*0.02
			if uv.y > 0.82: h = 0.1
			var lake := uv.distance_to(Vector2(0.65,0.5))
			if lake < 0.12: h = 0.28+lake/0.12*0.16
			if uv.distance_to(Vector2(0.18,0.3)) < 0.12: h = 0.92
			source[y*size.x+x] = (h-0.2)*12
	terrain.restore_heightfield(source,size)
	var water := Water.new()
	check(water.generate(terrain.map_renderer.normalized_heights,size,terrain.water_source_hash,Water.DEFAULTS).is_empty(),"Actual water generation for the forest fixture")
	check(terrain.install_water_layer(water).is_empty(),"Install generated water")
	var settings: Dictionary = Settings.DEFAULTS.duplicate()
	settings.count = 800
	settings.coverage = 75.0
	check(terrain.apply_tree_settings(settings).is_empty(),"Generate trees")
	editor._sync_from_terrain()
	editor._select_layer("trees")
	var forest = terrain.forest_view
	check(forest.positions.size() > 20 and forest.positions.size() <= 800,"Suitable ground receives a bounded forest")
	check(forest.attempts <= forest.MAX_ATTEMPTS and forest.get_child_count() <= 128,"Candidate work and GPU batches are bounded")
	var positions: PackedVector2Array = forest.positions.duplicate()
	var scales: PackedFloat32Array = forest.scales.duplicate()
	var kinds: PackedByteArray = forest.kinds.duplicate()
	var valid := true
	for i in range(positions.size()):
		var uv := positions[i]
		if uv.y > 0.82 or uv.distance_to(Vector2(0.18,0.3)) < 0.115: valid = false
		var site: Vector2 = terrain.map_renderer.forest_site(uv,scales[i]*0.34+0.06)
		if site.x <= 0.215 or site.x >= 0.78 or site.y > tan(deg_to_rad(26.25)): valid = false
		var region: Vector2 = terrain.map_renderer.regions.sample(uv,site.x)
		var local_line: float = minf(0.78-(1.0-region.x)*0.1,terrain.texture_settings.snow_height/100.0-(1.0-region.x)*0.14-0.04)
		if site.x >= local_line: valid = false
	check(valid,"Forests avoid sea, snowy ground, steep terrain and wet canopy footprints")
	var wet := -1
	for i in range(source.size()):
		if water.mask_bytes[i*4+1] > 200 and terrain.map_renderer.normalized_heights[i] > 0.25: wet = i; break
	check(wet >= 0,"Fixture contains a real generated inland lake")
	if wet >= 0:
		check(terrain.map_renderer.forest_site((Vector2(wet%size.x,wet/size.x)+Vector2.ONE*0.5)/Vector2(size),0.1).x < 0,"Trees reject inland lake water")
	var builds: int = forest.layout_builds
	var region_field = terrain.map_renderer.regions
	var texture_variant: Dictionary = terrain.texture_settings.duplicate()
	texture_variant.variation += 1
	terrain.map_renderer.set_texturing(texture_variant,terrain.map_seed,true)
	forest.refresh(terrain)
	check(terrain.map_renderer.regions == region_field and forest.layout_builds == builds,"Texture variation reuses climate without moving forests")
	terrain.map_renderer.set_texturing(terrain.texture_settings,terrain.map_seed,true)
	var overview_cover: ImageTexture = forest.cover_texture
	check(overview_cover != null and overview_cover.get_image().has_mipmaps(),"Forest overview has a filtered coverage mask")
	var old_max: float = rig.max_zoom
	rig.max_zoom = 2048.0
	rig._zoom = 1.0
	rig._apply_zoom()
	check(forest.detail == 0.0,"Full overview uses forest shading instead of tiny meshes")
	var no_meshes := true
	for child in forest.get_children():
		if child.visible: no_meshes = false
	check(no_meshes,"Overview skips individual tree draws")
	var unit_size: float = minf(96.0/192.0,72.0/20.0)*terrain.tree_settings.size
	var pixel_height: float = root.get_visible_rect().size.y
	rig._zoom = rig._fit_size/(unit_size*pixel_height/8.0)
	rig._apply_zoom()
	check(absf(forest.detail-0.5) < 0.01,"Mid-range zoom crossfades forest shading and geometry")
	check(absf(float(terrain.map_renderer.material.get_shader_parameter("forest_overview"))-0.5) < 0.01,"Ground and trees share complementary fade amounts")
	rig._zoom = rig._fit_size/8.0
	rig._apply_zoom()
	check(forest.detail == 1.0,"Close zoom shows complete tree geometry")
	check(forest.cover_texture == overview_cover and forest.layout_builds == builds,"Zoom reuses both placements and overview mask")
	rig.max_zoom = old_max
	terrain.map_paint.begin_stroke()
	terrain.map_paint.stamp(Vector2(0.5,0.5),terrain.map_size,4,Color(0.2,0.5,0.2))
	terrain.map_paint.refresh()
	terrain.refresh_water_layer()
	check(forest.layout_builds == builds,"Manual color strokes do not rebuild tree placement")
	for zoom in [1.0,2.0,4.0]:
		rig._zoom = zoom
		rig._apply_zoom()
	check(forest.layout_builds == builds and forest.positions == positions,"Zoom only moves roots; no placement regeneration")
	check(forest.material.get_shader_parameter("relief_amount") == terrain.map_renderer.visible_relief,"Tree roots share the terrain relief state")
	terrain.set_raw_height_view(true)
	check(not forest.visible,"Raw height inspection hides trees")
	terrain.set_raw_height_view(false)
	check(forest.visible and forest.positions == positions,"Leaving raw view restores the forest")
	terrain.regenerate()
	check(forest.positions == positions and forest.scales == scales and forest.kinds == kinds,"Same world/settings reproduce every tree")
	var original_hash: String = terrain.water_source_hash
	editor._forest_panel.controls.variation.value = 7
	await process_frame
	editor._forest_panel.generate()
	check(terrain.tree_settings.variation == 7 and forest.positions != positions,"Variation changes the forest")
	check(terrain.height_samples == source and terrain.water_source_hash == original_hash and terrain.water_layer == water,"Trees preserve source terrain and generated water")
	positions = forest.positions.duplicate()
	editor._layer_buttons.trees[1].button_pressed = true
	editor._forest_panel.new_variation()
	check(terrain.tree_settings.variation == 7 and forest.positions == positions,"Tree layer lock protects settings")
	editor._layer_buttons.trees[1].button_pressed = false
	editor._layer_buttons.trees[0].button_pressed = false
	check(not forest.visible,"Tree layer visibility works")
	check(not terrain.map_renderer.material.get_shader_parameter("forest_enabled"),"Hiding Trees also hides overview shading")
	editor._layer_buttons.trees[0].button_pressed = true
	check(forest.visible,"Tree layer restores visibility")
	var save_error: String = editor.save_world("res://.test-runtime/forest.world.json")
	check(save_error.is_empty(),"World save includes forest settings: "+save_error)
	check(editor.load_world("res://.test-runtime/forest.world.json").is_empty() and forest.positions == positions and terrain.tree_settings.variation == 7,"JSON reload recreates the same forest")
	var saved: Dictionary = Document.capture(terrain)
	var old := saved.duplicate(true)
	old.version = 13
	old.erase("tree_settings")
	check(Document.apply(terrain,old).is_empty() and not terrain.tree_settings.enabled and not forest.visible,"Earlier saves stay tree-free until requested")
	var bad := saved.duplicate(true)
	bad.tree_settings.count = 20001
	check(not Document.apply(terrain,bad).is_empty() and not terrain.tree_settings.enabled,"Excessive tree budget fails before changing live state")
	check(Document.apply(terrain,saved).is_empty(),"Restore forest")
	editor._sync_from_terrain()
	await process_frame
	var before: int = terrain.tree_settings.variation
	editor._forest_panel.new_variation()
	check(terrain.tree_settings.variation == before+1,"New variation commits the next seed")
	var current: Dictionary = terrain.tree_settings.duplicate()
	var empty := current.duplicate()
	empty.count = 0
	check(terrain.apply_tree_settings(empty).is_empty() and forest.positions.is_empty() and forest.get_child_count() == 0,"Zero budget removes the rendered forest")
	check(forest.cover_texture == null and not terrain.map_renderer.material.get_shader_parameter("forest_enabled"),"Zero budget also clears overview shading")
	check(terrain.apply_tree_settings(current).is_empty(),"Restore tree budget")
	var legacy := Manifest.capture(Manifest._layers_for_version(5),"forest.terrain.json","paint")
	legacy.version = 5
	var legacy_path := "res://.test-runtime/forest-v5.world.json"
	check(Manifest.save_file(legacy_path,legacy).is_empty(),"Legacy manifest fixture")
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
	var migrated := Manifest.load_file(legacy_path)
	check(migrated.error.is_empty() and migrated.document.layers.size() == 6 and FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes,"Layer migration adds trees without rewriting the source")
	if DisplayServer.get_name() != "headless":
		rig._reset_view()
		await process_frame
		await RenderingServer.frame_post_draw
		var overview := root.get_texture().get_image()
		overview.save_png("res://.test-runtime/forest-overview.png")
		editor._layer_buttons.trees[0].button_pressed = false
		for i in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var bare := root.get_texture().get_image()
		var shaded_pixels := 0
		# Exclude panels and checkbox pixels; only compare the map area.
		for y in range(160,mini(760,overview.get_height())):
			for x in range(260,mini(900,overview.get_width())):
				var a := overview.get_pixel(x,y)
				var b := bare.get_pixel(x,y)
				if Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b)) > 0.015: shaded_pixels += 1
		check(shaded_pixels > 50,"Overview renders forest coverage without individual tree geometry")
		editor._layer_buttons.trees[0].button_pressed = true
		rig._zoom = rig._fit_size/(unit_size*pixel_height/8.0)
		rig._apply_zoom()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-runtime/forest-transition.png")
		var uv: Vector2 = forest.positions[forest.positions.size()/2]
		rig.max_zoom = 2048.0
		rig.closest_view_size = 1.0
		rig._zoom = rig._fit_size/3.0
		rig._apply_zoom()
		rig.position = Vector3((uv.x-0.5)*96,0,(uv.y-0.5)*72)
		rig.position.y = terrain.visible_surface_height(uv)+0.35
		rig._fit_depth()
		await process_frame
		await RenderingServer.frame_post_draw
		var shown := root.get_texture().get_image()
		shown.save_png("res://.test-runtime/forest-close.png")
		forest.hide()
		for i in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var hidden := root.get_texture().get_image()
		var changed := 0
		var leaves := 0
		for y in range(shown.get_height()):
			for x in range(shown.get_width()):
				var color := shown.get_pixel(x,y)
				var background := hidden.get_pixel(x,y)
				if Vector3(color.r,color.g,color.b).distance_to(Vector3(background.r,background.g,background.b)) < 0.04: continue
				changed += 1
				if color.g > color.r*1.1 and color.g > color.b*1.2: leaves += 1
		check(changed > 100 and leaves > changed*0.4,"Instanced trees render colored leaves, not black silhouettes")
		forest.show()
	world.free()
	await process_frame
	print("Forest generation: %d failures" % failures)
	quit(1 if failures else 0)
