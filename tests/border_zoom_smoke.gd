extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Border zoom verification requires GPU rendering.")
		quit(1)
		return
	root.size = Vector2i(512,512)
	var layer := Provinces.new()
	layer.size = Vector2i(129,129)
	layer.source_hash = "a".repeat(64)
	layer.ids.resize(129*129)
	for y in range(129):
		for x in range(129): layer.ids[y*129+x] = 1 if x < 64 else 2
	layer.records.assign([{"id":1,"name":"West","kind":"land"},{"id":2,"name":"East","kind":"land"}])
	if not layer._index_regions().is_empty():
		quit(1)
		return
	layer.assign_nation(1,layer.add_nation("West",Color(0.9,0.06,0.03)))
	layer.assign_nation(2,layer.add_nation("East",Color(0.03,0.15,0.95)))
	var surface := MeshInstance3D.new()
	root.add_child(surface)
	var renderer := Renderer.new(surface)
	var heights := PackedFloat32Array()
	heights.resize(layer.ids.size())
	heights.fill(0.5)
	renderer.set_heightfield(heights,layer.size,Vector2(128,128),0,1,2)
	renderer.material.set_shader_parameter("province_fill",false)
	renderer.set_provinces(layer,true)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera)
	camera.position = Vector3(0,100,0)
	camera.rotation_degrees = Vector3(-90,0,0)
	camera.current = true
	for ocean in [false,true]:
		if ocean:
			layer = layer.editable_copy()
			for record in layer.records:
				record.kind = "ocean"
				record.nation_id = 0
			layer.ocean_generated = true
			layer._index_regions()
			heights.fill(0.1)
			renderer.set_heightfield(heights,layer.size,Vector2(128,128),0,1,2)
			renderer.set_provinces(layer,true)
		for zoom_size in [24.0,12.0,6.0]:
			camera.size = zoom_size
			for i in range(5): await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			var center := camera.unproject_position(Vector3((64.0/129.0-0.5)*128.0,0.06,0.0))
			center *= Vector2(frame.get_size())/root.get_visible_rect().size
			var widest := 0
			var narrowest := 999
			for y in range(192,320):
				var dark_pixels := 0
				for x in range(maxi(0,int(center.x)-10),mini(frame.get_width(),int(center.x)+11)):
					var color := frame.get_pixel(x,y)
					if maxf(color.r,maxf(color.g,color.b)) < 0.15: dark_pixels += 1
				widest = maxi(widest,dark_pixels)
				narrowest = mini(narrowest,dark_pixels)
			if narrowest < 1 or widest > (6 if ocean else 5):
				failures += 1
				push_error("Solid lines must remain continuous and bounded: "+str([ocean,zoom_size,narrowest,widest]))
			print("Solid border pixels: ocean=",ocean," camera=",zoom_size," min/max=",narrowest,"/",widest)
	for record in layer.records:
		record.kind = "land"
		record.nation_id = record.id
	layer._index_regions()
	renderer.set_provinces(layer,true)
	heights.fill(0.5)
	renderer.set_heightfield(heights,layer.size,Vector2(128,128),0,1,2)
	var settings: Dictionary = preload("res://scripts/domain/border_appearance.gd").DEFAULTS.duplicate()
	settings.nation_width = 7.0
	settings.distant_scale = 0.2
	renderer.set_border_appearance(settings)
	camera.size = 128.0
	var overview := await _coverage(camera)
	camera.size = 6.0
	var close := await _coverage(camera)
	if overview >= close*0.65 or close < 1.0:
		failures += 1
		push_error("Overview borders must become thinner: "+str([overview,close]))
	settings.nation_width = 0.0
	renderer.set_border_appearance(settings)
	var hidden := await _coverage(camera)
	if hidden > 0.01:
		failures += 1
		push_error("Zero thickness must hide nation lines.")
	print("Zoom coverage overview/close/hidden: ",overview,"/",close,"/",hidden)
	print("Solid border zoom: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func _coverage(camera: Camera3D) -> float:
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var center := camera.unproject_position(Vector3((64.0/129.0-0.5)*128.0,0.06,0.0))
	center *= Vector2(frame.get_size())/root.get_visible_rect().size
	var sum := 0.0
	for y in range(192,320):
		var background := frame.get_pixel(int(center.x)+12,y).r
		for x in range(int(center.x)-10,int(center.x)+11):
			sum += maxf(0.0,background-frame.get_pixel(x,y).r)/maxf(0.01,background-0.055)
	return sum/128.0
