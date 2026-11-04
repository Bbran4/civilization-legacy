extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
var failures := 0
var camera: Camera3D
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func capture() -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func sample(image: Image, uv: Vector2) -> Color:
	var point := (uv-Vector2.ONE*0.5)*90.0
	var screen := camera.unproject_position(Vector3(point.x,0,point.y))*Vector2(image.get_size())/root.get_visible_rect().size
	return image.get_pixelv(Vector2i(screen))
func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.size = Vector2i(600,600)
	var layer := Provinces.new()
	layer.size = Vector2i(3,3)
	layer.ids = PackedInt32Array([2,2,2,2,1,2,2,2,2])
	layer.records.assign([{"id":1,"name":"Island","kind":"land"},{"id":2,"name":"Sea","kind":"ocean"}])
	layer._index_regions()
	layer.assign_nation(1,layer.add_nation("Island",Color(1,0,0)))
	var surface := MeshInstance3D.new()
	root.add_child(surface)
	var renderer := Renderer.new(surface)
	var heights := PackedFloat32Array([0.19,0.19,0.19,0.19,0.8,0.19,0.19,0.19,0.19])
	renderer.set_heightfield(heights,layer.size,Vector2(90,90),0,1,2)
	renderer.set_provinces(layer,true)
	camera = Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0,100,0)
	camera.rotation_degrees = Vector3(-90,0,0)
	camera.size = 90
	camera.current = true
	var image := await capture()
	# The geographic threshold lies near UV .828, not the categorical edge at .667.
	for uv in [Vector2(0.72,0.5),Vector2(0.5,0.72),Vector2(0.72,0.72)]:
		var color := sample(image,uv)
		check(color.r > color.b*1.5,"Island fill reaches the interpolated coastline: "+str(uv))
	var categorical_edge := sample(image,Vector2(2.0/3.0,0.5))
	check(categorical_edge.r > 0.3,"Obsolete categorical coastline leaves no outline inside the island")
	var coast := sample(image,Vector2((1.0+(0.8-0.2)/(0.8-0.19)+0.5)/3.0,0.5))
	check(maxf(coast.r,maxf(coast.g,coast.b)) < 0.2,"Outline follows the interpolated height threshold")
	var sea := sample(image,Vector2(0.86,0.5))
	check(sea.b > sea.r,"Ocean fill stays beyond the real coast")
	# A narrow land range makes the true coast fall inside the categorical region.
	heights[4] = 0.21
	heights[0] = 0.0
	heights[1] = 0.0
	heights[2] = 0.0
	heights[3] = 0.0
	heights[5] = 0.0
	heights[6] = 0.0
	heights[7] = 0.0
	heights[8] = 0.0
	renderer.set_heightfield(heights,layer.size,Vector2(90,90),0,1,2)
	image = await capture()
	sea = sample(image,Vector2(0.60,0.5))
	check(sea.b > sea.r,"Province cannot spill past the coast into water")
	# Unassigned lake holes must also use the water field's contour.
	heights.fill(0.5)
	renderer.set_heightfield(heights,layer.size,Vector2(90,90),0,1,2)
	layer.ids = PackedInt32Array([1,1,1,1,0,1,1,1,1])
	layer.border_revision += 1
	layer._texture = null
	layer.border_geometry = null
	renderer.set_provinces(layer,true)
	var water_image := Image.create(3,3,false,Image.FORMAT_RGBA8)
	water_image.fill(Color(0,0,0,0))
	water_image.set_pixel(1,1,Color(0,1,0,1))
	var water = load("res://scripts/domain/terrain_water_layer.gd").new()
	water.mask_size = Vector2i(3,3)
	water.mask_bytes = water_image.get_data()
	renderer.set_water_layer(water,true)
	image = await capture()
	check(sample(image,Vector2(0.5,0.5)).b > sample(image,Vector2(0.5,0.5)).r,"Lake remains water")
	check(sample(image,Vector2(0.72,0.72)).r > sample(image,Vector2(0.72,0.72)).b,"Land around lake remains assigned")
	# Hiding water artwork does not change the geographic province footprint.
	renderer.set_water_layer(water,false)
	image = await capture()
	check(sample(image,Vector2(0.5,0.5)).r < 0.7,"Hidden water does not fill lake with a land province")
	check(layer.ids == PackedInt32Array([1,1,1,1,0,1,1,1,1]),"Rendering never changes province identities")
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	image.save_png("res://.test-runtime/province-geography.png")
	print("Province/geography alignment: %d failures" % failures)
	quit(1 if failures else 0)
