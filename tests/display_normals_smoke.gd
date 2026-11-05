extends SceneTree
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func capture() -> Image:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Display normals require the GPU renderer.")
		quit(1)
		return
	var node := MeshInstance3D.new()
	root.add_child(node)
	var renderer := Renderer.new(node)
	var size := Vector2i(2050,129)
	var heights := PackedFloat32Array()
	heights.resize(size.x*size.y)
	for y in range(size.y):
		for x in range(size.x): heights[y*size.x+x] = (0.5+0.002*sin(float(x)/size.x*TAU*410))*40
	renderer.set_heightfield(heights,size,Vector2(192,12),0,40,2)
	renderer.set_relief(1)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4
	camera.position = Vector3(0,100,0)
	camera.rotation_degrees = Vector3(-90,0,0)
	camera.current = true
	var detailed := await capture()
	var flat := Image.create(3,3,false,Image.FORMAT_RF)
	flat.fill(Color(20,0,0))
	renderer.material.set_shader_parameter("display_heights",ImageTexture.create_from_image(flat))
	var flattened := await capture()
	var difference := 0.0
	var count := 0
	for y in range(50,detailed.get_height()-50):
		for x in range(50,detailed.get_width()-50):
			difference += absf(detailed.get_pixel(x,y).r-flattened.get_pixel(x,y).r)
			count += 1
	check(difference/count > 0.02,"Actual terrain shader retains full-resolution normal detail at full relief.")
	renderer.material.set_shader_parameter("display_heights",renderer.display_texture)
	# A known ramp checks world-unit slopes and one-sided derivatives at edges.
	var ramp := PackedFloat32Array()
	ramp.resize(17*17)
	for y in range(17):
		for x in range(17): ramp[y*17+x] = 30.0+20.0*x/16.0+10.0*y/16.0
	renderer.set_heightfield(ramp,Vector2i(17,17),Vector2(192,192),0,100,2)
	var diagnostic := Shader.new()
	diagnostic.code = 'shader_type spatial; render_mode unshaded,cull_disabled;\n#include "res://scripts/rendering/display_normals.gdshaderinc"
void fragment(){ ALBEDO=display_normal(UV,vec2(192.0),vec2(0.0))*0.5+0.5; }'
	var material := ShaderMaterial.new()
	material.shader = diagnostic
	material.set_shader_parameter("display_heights",renderer.display_texture)
	material.set_shader_parameter("display_texel_size",Vector2.ONE/17)
	node.material_override = material
	camera.size = 192
	var normals := await capture()
	var expected := Vector3(-20.0*17/16/192,1.0,-10.0*17/16/192).normalized()*0.5+Vector3.ONE*0.5
	var c := normals.get_pixel(normals.get_width()/2,normals.get_height()/2)
	check(Vector3(c.r,c.g,c.b).distance_to(expected) < 0.02,"Normals use world-space elevation and horizontal distances.")
	var output := OS.get_environment("DISPLAY_OUTPUT")
	if not output.is_empty():
		detailed.save_png(output.path_join("fine-normal-regression.png"))
		flattened.save_png(output.path_join("flattened-normal-control.png"))
	node.free()
	print("Full-resolution display normals: %d failures (mean lighting difference %.4f)" % [failures,difference/count])
	quit(1 if failures else 0)
