extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var Grid = load("res://scripts/domain/heightmap_grid.gd")
	var corners := PackedFloat32Array([0,0,0,10])
	var previous := Vector2(0.1,0.1)
	for point in Grid.split_surface_segment(previous,Vector2(0.9,0.9),Vector2i(2,2)):
		check(absf(Grid.sample(corners,Vector2i(2,2),(previous+point)*0.5)-0.5*(Grid.sample(corners,Vector2i(2,2),previous)+Grid.sample(corners,Vector2i(2,2),point))) < 0.0001,"Draped segments remain on individual mesh triangles")
		previous = point
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	var rig = world.get_node("CameraRig")
	terrain.map_size = Vector2(192,144)
	terrain.resolution = 128
	terrain.elevation = 32
	var size = load("res://scripts/domain/heightmap_grid.gd").sample_size_for(terrain.map_size,128)
	var source := PackedFloat32Array()
	source.resize(size.x*size.y)
	for y in range(size.y):
		for x in range(size.x):
			var uv := Vector2(x,y)/Vector2(size-Vector2i.ONE)
			var h := 0.13+0.65*exp(-((uv-Vector2(0.5,0.5))*4.0).length_squared())
			source[y*size.x+x] = (h-0.2)*32.0
	terrain.restore_heightfield(source,size)
	editor._sync_from_terrain()
	var renderer = terrain.map_renderer
	var mesh_id: int = renderer._relief_mesh.get_instance_id()
	for zoom in [1.0,2.0,4.0]:
		rig._zoom = zoom
		rig._apply_zoom()
		var amount: float = 1.0-terrain.overview_blend
		check(absf(amount-(0.0 if zoom == 1 else (0.5 if zoom == 2 else 1.0))) < 0.001,"Zoom drives smooth relief")
		check(renderer._relief_mesh.get_instance_id() == mesh_id,"Zoom reuses the prepared mesh")
		for uv in [Vector2(0.35,0.4),Vector2(0.5,0.5),Vector2(0.65,0.7)]:
			var point := Vector3((uv.x-0.5)*192,terrain.visible_surface_height(uv),(uv.y-0.5)*144)
			var screen: Vector2 = rig._camera.unproject_position(terrain.to_global(point))
			var hit: Variant = terrain.ray_surface_hit(rig._camera.project_ray_origin(screen),rig._camera.project_ray_normal(screen))
			check(hit != null and hit.distance_to(terrain.to_global(point)) < 0.02,"Picking follows the rendered mesh at zoom "+str(zoom))
		check(renderer.surface.mesh == (renderer._overview_mesh if zoom == 1 else renderer._relief_mesh),"Flat overview uses a cheap plane; close view reuses relief grid")
		check(terrain.height_samples == source,"Relief never mutates saved heights")
		if DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://.test-runtime")
			root.get_texture().get_image().save_png("res://.test-runtime/relief-"+str(int(zoom))+".png")
	# Render a solid political border over the raised ridge, not over the old plane.
	var layer = load("res://scripts/domain/world_provinces.gd").new()
	layer.size = size
	layer.ids.resize(source.size())
	for y in range(size.y):
		for x in range(size.x): layer.ids[y*size.x+x] = 1 if x < size.x/2 else 2
	layer.records.assign([{"id":1,"name":"West","kind":"land"},{"id":2,"name":"East","kind":"land"}])
	layer._index_regions()
	layer.assign_nation(1,layer.add_nation("West",Color(0.9,0.03,0.03)))
	layer.assign_nation(2,layer.add_nation("East",Color(0.03,0.03,0.9)))
	renderer.set_provinces(layer,true)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var path: PackedVector2Array = layer.border_geometry.paths[0].points
		var uv_border: Vector2 = (path[0]+path[-1])*0.5/Vector2(size)
		var border_point := Vector3((uv_border.x-0.5)*192,renderer.visible_height(uv_border)+0.06,(uv_border.y-0.5)*144)
		var image := root.get_texture().get_image()
		var screen: Vector2 = rig._camera.unproject_position(border_point)*Vector2(image.get_size())/root.get_visible_rect().size
		var darkest := 1.0
		for y in range(int(screen.y)-2,int(screen.y)+3):
			for x in range(int(screen.x)-2,int(screen.x)+3):
				if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
				var color := image.get_pixel(x,y)
				darkest = minf(darkest,maxf(color.r,maxf(color.g,color.b)))
		check(darkest < 0.2,"Political border is rendered on the raised ridge")
	check(renderer.mesh_size.x <= 513 and renderer.mesh_size.y <= 513,"Mesh capacity is bounded")
	check(renderer.surface.custom_aabb.end.y > terrain.visible_surface_height(Vector2(0.5,0.5)),"Culling bounds contain raised terrain")
	check(terrain.ray_surface_hit(Vector3(10000,1000,10000),Vector3.DOWN) == null,"Rays outside the map miss")
	rig._yaw = 30
	rig._pitch = 45
	rig._apply_zoom()
	editor._select_layer("paint")
	editor._paint_brush.enabled.button_pressed = true
	var uv := Vector2(0.45,0.55)
	var point := Vector3((uv.x-0.5)*192,terrain.visible_surface_height(uv),(uv.y-0.5)*144)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = rig._camera.unproject_position(point)
	editor._paint_brush.handle_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	editor._paint_brush.handle_input(up)
	check(terrain.map_paint.image.get_pixelv(Vector2i(uv*1023)).a > 0.1,"Painting hits the tilted raised surface")
	terrain.set_raw_height_view(true)
	check(terrain.visible_surface_height(uv) == 0 and renderer.material.get_shader_parameter("relief_amount") == 0,"Raw heights remain flat")
	terrain.set_raw_height_view(false)
	check(terrain.visible_surface_height(uv) > 0,"Leaving raw view restores current zoom relief")
	# Controlled hydraulic fixture verifies water elevation is used, not the carved bed.
	var water = load("res://scripts/domain/terrain_water_layer.gd").new()
	water.mask_size = size
	water.mask_bytes.resize(source.size()*4)
	water.surface_levels.resize(source.size())
	water.surface_levels.fill(-1)
	for y in range(size.y/3,size.y*2/3):
		for x in range(size.x/3,size.x*2/3):
			var i: int = y*size.x+x
			water.mask_bytes[i*4+1] = 255
			water.surface_levels[i] = 0.9
	renderer.set_water_layer(water,true)
	check(absf(renderer.visible_height(Vector2(0.5,0.5))-22.4) < 0.01,"Visible water uses its saved hydraulic level")
	renderer.set_water_layer(water,false)
	check(renderer.visible_height(Vector2(0.5,0.5)) < 22.4,"Hiding water reveals the bed")
	world.free()
	print("Zoom relief smoke: %d failures" % failures)
	quit(1 if failures else 0)
