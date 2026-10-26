extends SceneTree
const View = preload("res://scripts/rendering/terrain_hydrology_view.gd")
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _capture(name_text: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://.godot/river-surface-" + name_text + ".png")
	return image
func _energy(image: Image) -> float:
	var total: float = 0
	var center := Vector2i(root.size / 2)
	for y in range(center.y - 8, center.y + 9):
		for x in range(center.x - 8, center.x + 9):
			total += image.get_pixel(x, y).g
	return total
func _run() -> void:
	if DisplayServer.get_name() != "headless":
		var world := Node3D.new()
		root.add_child(world)
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color.BLACK
		environment.environment = settings
		world.add_child(environment)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 12
		camera.near = 0.01
		camera.far = 50
		world.add_child(camera)
		camera.position = Vector3(0, 10, 10)
		camera.look_at(Vector3.ZERO)
		camera.current = true
		var view = View.new()
		world.add_child(view)
		var vertices := PackedVector3Array([Vector3(-4, 0, -0.6), Vector3(-4, 0, 0.6), Vector3(4, 0, -0.6), Vector3(4, 0, 0.6)])
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 8), Vector2(1, 8)])
		var data := PackedVector2Array([Vector2(-10, 0), Vector2(-10, 0), Vector2(-10, 0), Vector2(-10, 0)])
		var colours := PackedColorArray([Color(0.15, 0, 0), Color(0.15, 0, 0), Color(0.15, 0, 0), Color(0.15, 0, 0)])
		var node = view._water_node("TestRiver", vertices, PackedInt32Array([0, 1, 2, 1, 3, 2]), colours, Color("367d91"), 3, uvs, data)
		var material: ShaderMaterial = node.material_override
		material.set_shader_parameter("river_mode", true)
		material.set_shader_parameter("map_size", Vector2(20, 20))
		var field := Image.create(2, 2, false, Image.FORMAT_RF)
		field.fill(Color(0, 0, 0))
		var texture := ImageTexture.create_from_image(field)
		material.set_shader_parameter("height_coarse", texture)
		material.set_shader_parameter("height_fine", texture)
		var first: Image = await _capture("flow-a")
		await create_timer(0.25).timeout
		var second: Image = await _capture("flow-b")
		_check(_energy(first) > 10, "The animated river must be visible before testing occlusion.")
		var difference: float = 0
		for y in range(320, 480, 2):
			for x in range(400, 880, 2):
				difference += absf(first.get_pixel(x, y).g - second.get_pixel(x, y).g)
		_check(difference > 5, "River surface detail must move over time.")
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(4, 4, 4)
		var black := StandardMaterial3D.new()
		black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		black.albedo_color = Color.BLACK
		mesh.material = black
		box.mesh = mesh
		box.position = Vector3(0, 2, 0)
		world.add_child(box)
		var hidden: Image = await _capture("occluded")
		_check(_energy(hidden) < 0.01, "River fragments must fail the depth test behind foreground terrain or objects.")
		world.queue_free()
		await process_frame
	var game = load("res://scenes/main.tscn").instantiate()
	var terrain = game.get_node("Terrain")
	terrain.tree_population = 0
	root.add_child(game)
	await process_frame
	terrain.map_size = Vector2(512, 384)
	terrain.terrain_template = "Continents"
	terrain.island_enabled = false
	terrain.regenerate()
	var view = terrain.hydrology_view
	_check(not view.river_corridors.is_empty(), "The natural map must generate visible clipped river corridors.")
	for corridor in view.river_corridors:
		var midpoint: Vector2 = (corridor.a + corridor.b) * 0.5
		_check(is_nan(view.water_level_at(midpoint)), "River corridor centers must stop at visible lake/ocean edges instead of crossing water surfaces.")
	if view.rivers_mesh != null:
		var arrays: Array = view.rivers_mesh.mesh.surface_get_arrays(0)
		_check(arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size(), "River geometry must carry continuous flow coordinates.")
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			var point: Vector2 = Vector2(vertex.x, vertex.z) + terrain.map_size * 0.5
			_check(is_nan(view.water_level_at(point)), "River bank vertices must not extend across visible standing water.")
	var count: int = view.build_count
	var id: int = view.rivers_mesh.mesh.get_instance_id()
	terrain.detail.set_detail(1.5)
	view._process(0)
	_check(view._river_material.get_shader_parameter("height_fine") == terrain.detail.height_textures[2] and is_equal_approx(view._river_material.get_shader_parameter("field_blend"), 0.5) and view.build_count == count and view.rivers_mesh.mesh.get_instance_id() == id, "Rivers must track displayed terrain LODs through shader fields without rebuilding.")
	terrain.terrain_template = "Volcano"
	terrain.elevation = 80
	terrain.regenerate()
	var options: Dictionary = terrain.climate_settings.duplicate()
	options.latitude_span = 20
	options.rainfall_scale = 3
	terrain.apply_climate(options)
	var strongest: float = 0
	if terrain.hydrology_view.rivers_mesh != null:
		var arrays: Array = terrain.hydrology_view.rivers_mesh.mesh.surface_get_arrays(0)
		for colour in arrays[Mesh.ARRAY_COLOR]:
			strongest = maxf(strongest, colour.g)
	_check(strongest > 0.1, "Steep generated rivers must carry cascade/foam intensity into the water shader.")
	game.queue_free()
	await process_frame
	print("River surface checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
