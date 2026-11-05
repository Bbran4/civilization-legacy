extends SceneTree
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var node := MeshInstance3D.new()
	root.add_child(node)
	var renderer := Renderer.new(node)
	var source := PackedFloat32Array()
	source.resize(2050*2050)
	for y in range(2050):
		for x in range(2050):
			var h := 0.5+0.12*sin(x*0.021)*cos(y*0.027)-0.15*exp(-pow((x-1030.0)/2.0,2))
			source[y*2050+x] = h*20
	var original := source.duplicate()
	renderer.set_heightfield(source,Vector2i(2050,2050),Vector2(1024,1024),0,20,2)
	renderer.set_relief(1)
	var patches = renderer.patches
	check(patches.count == Vector2i(16,16) and patches.max_level == 4 and patches._meshes.size() == 5,"Large terrain uses shared density meshes across 16×16 patches.")
	check(renderer.surface_grid_size() == Vector2i(2049,2049) and renderer.surface.mesh == null and patches.root.visible,"Close geometry and draping support source-scale cells without drawing the old grid too.")
	var build_count: int = renderer.display_builds
	var worst_seam := 0.0
	var transitions := 0
	var largest_budget := 0
	for view in [1024.0,512.0,200.0,128.0,16.0,8.0]:
		for focus in [Vector2.ZERO,Vector2(17.3,-13.2),Vector2(490,-490)]:
			patches.update_view(focus,view,800,1.6,0.82)
			largest_budget = maxi(largest_budget,patches.triangle_count())
			for y in range(patches.count.y):
				for x in range(patches.count.x):
					var level: int = patches.levels[y*patches.count.x+x]
					for direction in [Vector2i.RIGHT,Vector2i.DOWN]:
						var neighbor: Vector2i = Vector2i(x,y)+direction
						if neighbor.x >= patches.count.x or neighbor.y >= patches.count.y: continue
						var other: int = patches.levels[neighbor.y*patches.count.x+neighbor.x]
						check(absi(level-other) <= 1,"Adjacent patch detail differs by at most one level.")
						if level != other: transitions += 1
						for t in [0.0,0.13,0.37,0.5,0.81,1.0]:
							var uv := Vector2(x+1,y+t)/Vector2(patches.count) if direction == Vector2i.RIGHT else Vector2(x+t,y+1)/Vector2(patches.count)
							worst_seam = maxf(worst_seam,absf(patches.sample_level(uv,level)-patches.sample_level(uv,other)))
	check(transitions > 0 and worst_seam < 0.0001,"Shared mesh edges remain equal during mixed-detail morphing.")
	check(largest_budget < 3000000,"Assigned detail stays bounded below 3 million assigned triangles rather than the full 8-million grid.")
	# Crossing a screen-density threshold starts the finer mesh on its parent plane.
	var before := PackedFloat32Array()
	patches.update_view(Vector2.ZERO,200.001,800,1.6,0.82)
	for y in range(20,81,10):
		for x in range(20,81,10): before.append(patches.sample(Vector2(x,y)/100.0))
	patches.update_view(Vector2.ZERO,199.999,800,1.6,0.82)
	var i := 0
	var jump := 0.0
	for y in range(20,81,10):
		for x in range(20,81,10):
			jump = maxf(jump,absf(before[i]-patches.sample(Vector2(x,y)/100.0)))
			i += 1
	check(jump < 0.001,"Crossing a detail threshold does not pop the surface.")
	patches.update_view(Vector2.ZERO,8,800,1.6,0.82)
	var channel := Vector2(1030.5/2050.0,1025.5/2050.0)
	var target: float = patches.raw_height(channel)
	var fine_error: float = absf(renderer.visible_height(channel)-target)
	renderer.set_chunking_enabled(false)
	var coarse_error: float = absf(renderer.visible_height(channel)-target)
	renderer.set_chunking_enabled(true)
	check(fine_error < coarse_error*0.5,"Source-scale close geometry resolves a narrow channel better than the old 512-cell mesh.")
	print("Narrow channel height error: coarse %.5f; patches %.5f" % [coarse_error,fine_error])
	check(renderer.display_builds == build_count and source == original,"Camera detail changes do not rebake or mutate height data.")
	if DisplayServer.get_name() != "headless": await _graphics(renderer,node)
	node.free()
	print("Terrain patches: %d failures; worst seam %.8f; threshold jump %.8f; maximum assigned triangles %d" % [failures,worst_seam,jump,largest_budget])
	quit(1 if failures else 0)
func _graphics(renderer: RefCounted,node: MeshInstance3D) -> void:
	root.msaa_3d = Viewport.MSAA_DISABLED
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 128
	camera.position = Vector3(23,100,-17)
	camera.rotation_degrees = Vector3(-90,0,0)
	camera.current = true
	renderer.update_detail(camera,Vector3(23,0,-17))
	# Keep a wide diagnostic camera over a close-view LOD layout to expose mixed edges.
	renderer.patches.update_view(Vector2.ZERO,8,800,1.6,1)
	renderer._bind_patch_materials()
	var shader := Shader.new()
	var code: String = Renderer.SHADER.code
	code = code.substr(0,code.find("void fragment()"))
	code = code.replace("render_mode cull_disabled, ambient_light_disabled, specular_disabled, fog_disabled;","render_mode unshaded, cull_disabled;")
	shader.code = code+'void fragment(){ ALBEDO=vec3(map_world_position.y/100.0); }'
	renderer.material.shader = shader
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(1,0,1)
	root.add_child(environment)
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var worst := 0.0
	var holes := 0
	for y in range(20,image.get_height()-20,7):
		for x in range(20,image.get_width()-20,7):
			var pixel := image.get_pixel(x,y)
			if pixel.r > 0.9 and pixel.b > 0.9 and pixel.g < 0.1: holes += 1
			var screen := (Vector2(x,y)+Vector2.ONE*0.5)*root.get_visible_rect().size/Vector2(image.get_size())
			var origin := camera.project_ray_origin(screen)
			var uv: Vector2 = Vector2(origin.x,origin.z)/renderer.map_extent+Vector2.ONE*0.5
			var expected: float = renderer.visible_height(uv)
			worst = maxf(worst,absf(pixel.r*100-expected))
	check(holes == 0 and worst < 0.35,"Actual GPU patch heights match CPU picking without visible seam holes.")
	print("GPU patch/CPU height error: %.5f; sampled holes: %d; rendered primitives: %d" % [worst,holes,RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	# A translated terrain owner must retain map-local UVs and patch geometry.
	node.position = Vector3(73,0,-29)
	camera.position += node.position
	renderer._bind_patch_materials()
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var translated := root.get_texture().get_image()
	var transform_error := 0.0
	for y in range(30,image.get_height()-30,13):
		for x in range(30,image.get_width()-30,13): transform_error = maxf(transform_error,absf(image.get_pixel(x,y).r-translated.get_pixel(x,y).r))
	check(transform_error < 0.02,"Translated terrain owners preserve the GPU patch field and camera framing.")
	var output := OS.get_environment("PATCH_OUTPUT")
	if not output.is_empty(): image.save_png(output.path_join("patch-height-validation.png"))
	camera.free()
	environment.free()
