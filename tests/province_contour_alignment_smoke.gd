extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Contour alignment requires GPU rendering.")
		quit(1)
		return
	root.size = Vector2i(600,600)
	var layer := Provinces.new()
	layer.size = Vector2i(3,3)
	layer.ids = PackedInt32Array([1,1,2,1,3,2,3,3,2])
	layer.source_hash = "a".repeat(64)
	for id in range(1,4): layer.records.append({"id":id,"kind":"land","name":str(id)})
	layer._index_regions()
	for color in [Color(0.9,0.03,0.03),Color(0.03,0.03,0.9),Color(0.03,0.9,0.03)]:
		var id: int = layer.add_nation("Nation "+str(layer.nations.size()),color)
		layer.assign_nation(id,id)
	var original := layer.ids.duplicate()
	var surface := MeshInstance3D.new()
	root.add_child(surface)
	var renderer := Renderer.new(surface)
	var appearance: Dictionary = preload("res://scripts/domain/border_appearance.gd").DEFAULTS.duplicate()
	appearance.province_width = 0.0
	appearance.nation_width = 0.0
	appearance.ocean_width = 0.0
	renderer.set_border_appearance(appearance)
	var heights := PackedFloat32Array([0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5])
	renderer.set_heightfield(heights,layer.size,Vector2(90,90),0,1,2)
	renderer.set_provinces(layer,true)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera)
	camera.position = Vector3(0,100,0)
	camera.rotation_degrees = Vector3(-90,0,0)
	camera.size = 90
	camera.current = true
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var examined := 0
	for path in layer.border_geometry.paths:
		for j in range(path.points.size()-1):
			var a: Vector2 = path.points[j]
			var b: Vector2 = path.points[j+1]
			var normal := Vector2(-(b-a).y,(b-a).x).normalized()
			for side in [-1,1]:
				var point: Vector2 = (a+b)*0.5+normal*0.04*side
				var world: Vector2 = (point/3.0-Vector2.ONE*0.5)*90
				var screen := camera.unproject_position(Vector3(world.x,0,world.y))*Vector2(image.get_size())/root.get_visible_rect().size
				var color := image.get_pixelv(Vector2i(screen))
				var actual := 1 if color.r > maxf(color.g,color.b) else (2 if color.b > color.g else 3)
				var expected: int = path.a if side > 0 else path.b
				if actual != expected:
					failures += 1
					push_error("Rendered fill must agree with its shared contour: "+str([point,actual,expected]))
				examined += 1
	if layer.ids != original or examined < 10: failures += 1
	print("GPU contour/fill alignment: ","PASS" if failures == 0 else "FAIL"," (",examined," side samples)")
	quit(0 if failures == 0 else 1)
