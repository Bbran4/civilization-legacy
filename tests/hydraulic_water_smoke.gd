extends SceneTree
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
func _initialize() -> void: run.call_deferred()
func frame() -> Color:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	return image.get_pixel(image.get_width()/2,image.get_height()/2)
func run() -> void:
	var ground := MeshInstance3D.new()
	root.add_child(ground)
	var renderer := Renderer.new(ground)
	var heights := PackedFloat32Array()
	heights.resize(65*65)
	heights.fill(0.35)
	renderer.set_heightfield(heights,Vector2i(65,65),Vector2(192,192),0,1,2)
	var water := Water.new()
	water.mask_size=Vector2i(65,65)
	water.mask_bytes.resize(heights.size()*4)
	water.surface_levels.resize(heights.size())
	water.surface_levels.fill(-1)
	for y in range(20,45):
		for x in range(20,45):
			var i := y*65+x
			water.mask_bytes[i*4+1]=255
			water.surface_levels[i]=0.5
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(0,100,0)
	camera.rotation_degrees=Vector3(-90,0,0)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=120
	camera.current=true
	renderer.set_relief(1)
	renderer.set_water_layer(water,true)
	var wet := await frame()
	var ok: bool = renderer.material.next_pass == renderer.water_material and wet.b > wet.r+0.08 and is_equal_approx(renderer.visible_height(Vector2(0.5,0.5)),0.5)
	renderer.set_water_layer(water,false)
	var dry := await frame()
	ok = ok and renderer.material.next_pass == null and absf(dry.b-dry.r)<0.06 and is_equal_approx(renderer.visible_height(Vector2(0.5,0.5)),0.35)
	print("Water surface wet/dry ",wet," ",dry," PASS=",ok)
	quit(0 if ok else 1)
