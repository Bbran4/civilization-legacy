extends SceneTree
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	await terrain.wait_for_presentation()
	terrain.resolution = 2049
	var size := Vector2i(2050,1025)
	var source := PackedFloat32Array()
	source.resize(size.x*size.y)
	for y in range(size.y):
		for x in range(size.x):
			var uv := Vector2(x,y)/Vector2(size-Vector2i.ONE)
			var h := 0.35+0.3*exp(-(uv-Vector2.ONE*0.5).length_squared()/0.08)+0.012*sin(uv.x*40)*cos(uv.y*30)
			source[y*size.x+x] = (h-0.2)*terrain.elevation
	terrain.restore_heightfield(source,size)
	await terrain.wait_for_presentation()
	var renderer = terrain.map_renderer
	var rig = world.get_node("CameraRig")
	rig.max_zoom = 2048
	rig._pitch = 85
	var builds: int = renderer.display_builds
	var max_error := 0.0
	var started := Time.get_ticks_usec()
	for zoom in [1.0,2.0,4.0,16.0,64.0]:
		for position in [Vector2.ZERO,Vector2(33,-19)]:
			rig.position.x = position.x
			rig.position.z = position.y
			rig._zoom = zoom
			rig._apply_zoom()
			for offset in [Vector2.ZERO,Vector2(2,-3),Vector2(-3,2)]:
				var point: Vector2 = position+offset
				var uv: Vector2 = point/terrain.display_size()+Vector2.ONE*0.5
				var height: float = terrain.visible_surface_height(uv)
				var local := Vector3(point.x,height,point.y)
				var screen: Vector2 = rig._camera.unproject_position(terrain.to_global(local))
				var hit: Variant = terrain.ray_surface_hit(rig._camera.project_ray_origin(screen),rig._camera.project_ray_normal(screen))
				check(hit != null,"The displayed patch surface remains pickable across zoom and pan.")
				if hit != null: max_error = maxf(max_error,hit.distance_to(terrain.to_global(local)))
	var picking_usec := Time.get_ticks_usec()-started
	check(max_error < 0.02,"Actual camera picking follows morphed patch triangles.")
	check(renderer.display_builds == builds and terrain.height_samples == source,"Camera movement changes geometry without rebaking or mutating source heights.")
	var grid: Vector2i = renderer.surface_grid_size()
	var previous := Vector2(0.49,0.48)
	var drape_error := 0.0
	for point in Grid.split_surface_segment(previous,Vector2(0.54,0.55),grid):
		drape_error = maxf(drape_error,absf(renderer.visible_height((previous+point)*0.5)-(renderer.visible_height(previous)+renderer.visible_height(point))*0.5))
		previous = point
	check(drape_error < 0.0001,"Borders and brush previews split onto the actual patch triangles.")
	check(terrain.forest_view.material.get_shader_parameter("chunked_relief"),"Tree roots use the same patch sampler.")
	var layer = load("res://scripts/domain/world_provinces.gd").new()
	layer.size = size
	layer.ids.resize(source.size())
	for y in range(size.y):
		for x in range(size.x): layer.ids[y*size.x+x] = 1 if x < size.x/2 else 2
	layer.records.assign([{"id":1,"name":"West","kind":"land"},{"id":2,"name":"East","kind":"land"}])
	check(layer._index_regions().is_empty(),"Prepare a connected political border over the detailed ridge.")
	layer.assign_nation(1,layer.add_nation("West",Color(0.8,0.05,0.03)))
	layer.assign_nation(2,layer.add_nation("East",Color(0.03,0.1,0.8)))
	renderer.material.set_shader_parameter("province_fill",false)
	renderer.set_provinces(layer,true)
	check(renderer.borders.relief_grid == renderer.surface_grid_size(),"Political ribbons split at the finest patch triangles.")
	for child in renderer.borders.root.get_children(): check(child.material_override.get_shader_parameter("chunked_relief"),"Political materials receive the current patch sampler.")
	if DisplayServer.get_name() != "headless":
		rig.position.x = 0
		rig.position.z = 0
		rig._fit_depth()
		terrain.forest_view.hide()
		for i in range(5): await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var point := Vector3(0,renderer.visible_height(Vector2(0.5,0.5)),0)
		var pixel: Vector2 = rig._camera.unproject_position(point)*Vector2(image.get_size())/root.get_visible_rect().size
		var darkest := 1.0
		for y in range(int(pixel.y)-3,int(pixel.y)+4):
			for x in range(int(pixel.x)-3,int(pixel.x)+4):
				var c := image.get_pixel(x,y)
				darkest = minf(darkest,maxf(c.r,maxf(c.g,c.b)))
		check(darkest < 0.2,"Actual political border is visible on the raised patch surface.")
		var output := OS.get_environment("PATCH_OUTPUT")
		if not output.is_empty(): image.save_png(output.path_join("patch-border-validation.png"))
	terrain.set_raw_height_view(true)
	check(renderer.surface.mesh == renderer._overview_mesh and not renderer.patches.root.visible and terrain.visible_surface_height(Vector2(0.5,0.5)) == 0,"Raw view retains its flat inspection surface.")
	terrain.set_raw_height_view(false)
	var editor = world.get_node("Interface/Editor")
	editor.play_map()
	await process_frame
	check(editor._gameplay_map != null,"Chunked terrain opens in Play map.")
	if editor._gameplay_map != null:
		var player = editor._gameplay_map.get_node("Terrain")
		await player.wait_for_presentation()
		check(player.map_renderer.patches.enabled and player.height_samples == source,"Gameplay reconstructs chunked geometry from the unchanged authored source.")
		editor._return_from_map()
		await process_frame
	world.free()
	print("Patch integration: %d failures; picking error %.7f; drape error %.8f; 30 picking/view checks %.2f ms" % [failures,max_error,drape_error,picking_usec/1000.0])
	quit(1 if failures else 0)
