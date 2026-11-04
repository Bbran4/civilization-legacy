extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func capture() -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.size = Vector2i(600,600)
	var surface := MeshInstance3D.new()
	root.add_child(surface)
	var renderer := Renderer.new(surface)
	var layer := Provinces.new()
	layer.size = Vector2i(3,3)
	layer.ids = PackedInt32Array([1,1,1,1,1,1,1,1,1])
	layer.records.append({"id":1,"name":"Land","kind":"land"})
	layer._index_regions()
	var heights := PackedFloat32Array([0.201,0.9,0.201,0.9,0.201,0.9,0.201,0.9,0.201])
	renderer.set_heightfield(heights,layer.size,Vector2(90,90),0,32,2)
	renderer.set_provinces(layer,true)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0,100,0)
	camera.rotation_degrees = Vector3(-90,0,0)
	camera.size = 90
	camera.current = true
	renderer.material.set_shader_parameter("coast_width",12.0)
	var outlined := await capture()
	renderer.material.set_shader_parameter("coast_width",0.0)
	var plain := await capture()
	var changed := 0
	for y in range(plain.get_height()):
		for x in range(plain.get_width()):
			if outlined.get_pixel(x,y) != plain.get_pixel(x,y): changed += 1
	check(changed == 0,"No ghost coastlines where every sample is above sea level")
	layer.ids = PackedInt32Array([1,1,1,2,2,2,2,2,2])
	layer.records.append({"id":2,"name":"South","kind":"land"})
	layer._texture = null
	layer._index_regions()
	layer.assign_nation(1,layer.add_nation("North",Color(0.9,0.03,0.03)))
	layer.assign_nation(2,layer.add_nation("South",Color(0.03,0.03,0.9)))
	heights.fill(0.5)
	renderer.set_heightfield(heights,layer.size,Vector2(90,90),0,32,4)
	renderer.set_relief(1.0)
	renderer.set_provinces(layer,true)
	var path: PackedVector2Array = layer.border_geometry.paths[0].points
	var uv: Vector2 = (path[0]+path[-1])*0.5/Vector2(layer.size)
	var point := Vector3((uv.x-0.5)*90,renderer.visible_height(uv),(uv.y-0.5)*90)
	camera.position = point+Vector3(0,100,70)
	camera.look_at(point)
	camera.size = 1.5
	var frame := await capture()
	var screen := camera.unproject_position(point)*Vector2(frame.get_size())/root.get_visible_rect().size
	var inside := 0
	var outside := 0
	for x in range(int(screen.x)-60,int(screen.x)+61):
		for y in range(int(screen.y)-25,int(screen.y)+26):
			var color := frame.get_pixel(x,y)
			if maxf(color.r,maxf(color.g,color.b)) < 0.2:
				if absf(y-screen.y) <= 3: inside += 1
				else: outside += 1
	check(inside > 100 and outside == 0,"Deep-zoom border stays on its surface instead of floating off it")
	# Grazing slopes make the projected surface normal nearly zero. Extrusion
	# and depth bias must remain bounded rather than shooting spikes across view.
	for i in range(heights.size()): heights[i] = [0.21,0.6385714,0.99][i/3]
	renderer.set_heightfield(heights,layer.size,Vector2(90,90),0,100,4)
	renderer.set_relief(1.0)
	renderer.set_provinces(layer,true)
	point.y = renderer.visible_height(uv)
	camera.position = point+Vector3(0,100,70)
	camera.look_at(point)
	var grazing := await capture()
	screen = camera.unproject_position(point)*Vector2(grazing.get_size())/root.get_visible_rect().size
	var spikes := 0
	for x in range(int(screen.x)-60,int(screen.x)+61):
		for y in range(int(screen.y)-60,int(screen.y)+61):
			var color := grazing.get_pixel(x,y)
			if maxf(color.r,maxf(color.g,color.b)) < 0.2 and absf(y-screen.y) > 5: spikes += 1
	check(spikes == 0,"Grazing terrain does not produce unbounded border spikes")
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	frame.save_png("res://.test-runtime/border-deep-zoom.png")
	grazing.save_png("res://.test-runtime/border-grazing.png")
	print("Border artifacts: %d failures; ghost pixels %d; attached/stray pixels %d/%d; grazing spikes %d" % [failures,changed,inside,outside,spikes])
	quit(1 if failures else 0)
