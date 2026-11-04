extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func capture() -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func color_at(image: Image, terrain: Node, camera: Camera3D, uv: Vector2) -> Color:
	var extent: Vector2 = terrain.display_size()
	var point := Vector3((uv.x-0.5)*extent.x,terrain.visible_surface_height(uv),(uv.y-0.5)*extent.y)
	var pixel := camera.unproject_position(terrain.to_global(point))*Vector2(image.get_size())/root.get_visible_rect().size
	return image.get_pixelv(Vector2i(pixel).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))
func _run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.get_node("Interface").visible = false
	var terrain = world.get_node("Terrain")
	var rig = world.get_node("CameraRig")
	var sun: DirectionalLight3D = world.get_node("Sun")
	terrain.map_size = Vector2(96,72)
	terrain.resolution = 128
	terrain.elevation = 100
	var size = load("res://scripts/domain/heightmap_grid.gd").sample_size_for(terrain.map_size,128)
	var source := PackedFloat32Array()
	source.resize(size.x*size.y)
	for y in range(size.y):
		for x in range(size.x): source[y*size.x+x] = (0.30+float(x)/(size.x-1)*0.4-0.2)*100
	terrain.restore_heightfield(source,size)
	rig._reset_view()
	var renderer = terrain.map_renderer
	check(renderer.lighting.haze_strength < 0.0001,"Overhead map has no atmospheric veil")
	var texture_id: int = renderer._ground_library.get_instance_id()
	var regions_id: int = renderer.regions.get_instance_id()
	rig._zoom = 3.0
	rig._apply_zoom()
	check(renderer.lighting.haze_strength > 0 and renderer.lighting.haze_strength <= 0.1,"Oblique relief has restrained atmosphere")
	var sun_direction: Vector3 = renderer.material.get_shader_parameter("map_sun_direction")
	check(sun_direction.is_equal_approx(sun.global_basis.z.normalized()) and sun_direction.y > 0,"Shared sun direction follows the scene light above the ground")
	if terrain.forest_view != null:
		check(terrain.forest_view.material.get_shader_parameter("map_sun_direction") == sun_direction,"Foliage and terrain receive the same lighting snapshot")
	var focus: Vector3 = renderer.lighting.haze_focus
	rig.position.x += 2.0
	rig._fit_depth()
	var new_focus: Vector3 = renderer.lighting.haze_focus
	check(absf(new_focus.x-focus.x-2.0) < 0.001 and absf(new_focus.y-terrain.visible_surface_height(Vector2(new_focus.x/96.0+0.5,new_focus.z/72.0+0.5))) < 0.001,"Panning anchors atmospheric focus to displayed ground")
	check(renderer._ground_library.get_instance_id() == texture_id and renderer.regions.get_instance_id() == regions_id and terrain.height_samples == source,"Lighting changes reuse materials and preserve geography")
	if DisplayServer.get_name() != "headless":
		# Isolate the slope from tree silhouettes for the sun-direction comparison.
		if terrain.forest_view != null: terrain.forest_view.hide()
		renderer.material.set_shader_parameter("forest_enabled",false)
		sun.rotation_degrees = Vector3(-25,-90,0)
		rig._fit_depth()
		var left := color_at(await capture(),terrain,rig._camera,Vector2(0.5,0.5))
		sun.rotation_degrees = Vector3(-25,90,0)
		rig._fit_depth()
		var right := color_at(await capture(),terrain,rig._camera,Vector2(0.5,0.5))
		check(left.r+left.g+left.b > right.r+right.g+right.b+0.02,"Turning the sun changes actual rendered slope lighting")
		sun.rotation_degrees = Vector3(-52,-35,0)
		rig._fit_depth()
		var atmosphere := await capture()
		DirAccess.make_dir_recursive_absolute("res://.test-runtime")
		atmosphere.save_png("res://.test-runtime/lighting-relief.png")
		var far_uv := Vector2(0.5,0.25)
		var misty := color_at(atmosphere,terrain,rig._camera,far_uv)
		renderer.material.set_shader_parameter("map_haze_strength",0.0)
		var clear := color_at(await capture(),terrain,rig._camera,far_uv)
		check(Vector3(misty.r-clear.r,misty.g-clear.g,misty.b-clear.b).length() > 0.001,"Subtle haze changes distant ground pixels")
		terrain.set_raw_height_view(true)
		var raw := color_at(await capture(),terrain,rig._camera,Vector2(0.5,0.5))
		check(absf(raw.r-raw.g) < 0.005 and absf(raw.g-raw.b) < 0.005,"Raw height inspection bypasses lighting tint and atmosphere")
	world.free()
	var gameplay = load("res://scenes/gameplay_map.tscn").instantiate()
	gameplay.get_node("Terrain").resolution = 128
	gameplay.get_node("Terrain").graph_points = 1000
	root.add_child(gameplay)
	await process_frame
	var runtime = gameplay.get_node("Terrain").map_renderer
	var runtime_sun: DirectionalLight3D = gameplay.get_node("Sun")
	check(runtime.material.get_shader_parameter("map_sun_direction").is_equal_approx(runtime_sun.global_basis.z.normalized()) and absf(runtime.lighting.sky_strength-0.67) < 0.001,"Gameplay uses the same scene-driven lighting profile")
	gameplay.free()
	print("Map lighting: %d failures" % failures)
	quit(1 if failures else 0)
