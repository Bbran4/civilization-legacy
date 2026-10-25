extends SceneTree
const View = preload("res://scripts/rendering/terrain_geography_view.gd")
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _paths(points: Array, closed: bool = false) -> Array[Dictionary]:
	return [{"points": PackedVector2Array(points), "closed": closed}]

func _capture(name_text: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://.godot/coast-" + name_text + ".png")
	return image

func _energy(image: Image, point: Vector2i, radius: Vector2i) -> float:
	var result: float = 0
	for y in range(point.y - radius.y, point.y + radius.y + 1):
		for x in range(point.x - radius.x, point.x + radius.x + 1):
			result += image.get_pixel(x, y).r
	return result

func _gpu_fixture() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color.BLACK
	environment.environment = settings
	fixture.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 100
	fixture.add_child(camera)
	camera.position = Vector3(0, 20, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	var view = View.new()
	fixture.add_child(view)
	view.build_paths(_paths([Vector2(10, 2), Vector2(10, 18)]), Vector2(20, 20), 0, Color.WHITE)
	view._material.set_shader_parameter("max_half_width", 1.0)
	var widths: Array[float] = []
	var center := Vector2i(root.size / 2)
	for size_value in [20.0, 10.0, 5.0]:
		camera.size = size_value
		var image: Image = await _capture("width-" + str(int(size_value)))
		var energy: float = _energy(image, center, Vector2i(6, 10)) / 21.0
		widths.append(energy)
		_check(energy > 0.5 and energy < 2.5, "The soft ribbon must stay approximately one to two pixels wide.")
	_check(widths.max() - widths.min() < 0.4, "Projected ribbon width must stay stable across a fourfold zoom.")
	camera.size = 20
	camera.position = Vector3(0, 15, 15)
	camera.look_at(Vector3.ZERO)
	var visible: Image = await _capture("depth-visible")
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(6, 4, 6)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	mesh.material = black
	box.mesh = mesh
	box.position = Vector3(0, 2, 0)
	fixture.add_child(box)
	var hidden: Image = await _capture("depth-hidden")
	_check(_energy(visible, center, Vector2i(4, 15)) > 5, "Occlusion check must first see an unobstructed coast.")
	_check(_energy(hidden, center, Vector2i(4, 15)) < 0.01, "Foreground depth must fully hide the coastline, rather than drawing through it.")
	box.queue_free()
	await process_frame
	view.build_paths(_paths([Vector2(2, 10), Vector2(18, 10)]), Vector2(20, 20), 0, Color.WHITE)
	view._material.set_shader_parameter("surface_following", true)
	var low := Image.create(2, 2, false, Image.FORMAT_RF)
	low.fill(Color(2, 0, 0))
	var high := Image.create(2, 2, false, Image.FORMAT_RF)
	high.fill(Color(4, 0, 0))
	var low_texture := ImageTexture.create_from_image(low)
	var high_texture := ImageTexture.create_from_image(high)
	for blend in [0.0, 0.5, 1.0]:
		view.set_surface_fields(low_texture, high_texture, blend)
		var image: Image = await _capture("drape-" + str(blend))
		var location: Vector2i = Vector2i(camera.unproject_position(Vector3(0, 2 + blend * 2, 0)))
		_check(_energy(image, location, Vector2i(10, 3)) > 5, "The GPU ribbon must follow the displayed coarse/fine height blend.")
	# A coarse sea edge displaced from the fixed fine contour must project correctly.
	camera.position = Vector3(0, 20, 0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	view.build_paths(_paths([Vector2(8, 2), Vector2(8, 18)]), Vector2(20, 20), 0, Color.WHITE)
	view._material.set_shader_parameter("surface_following", true)
	for row in range(2):
		low.set_pixel(0, row, Color(-12, 0, 0))
		low.set_pixel(1, row, Color(8, 0, 0))
		high.set_pixel(0, row, Color(-8, 0, 0))
		high.set_pixel(1, row, Color(12, 0, 0))
	low_texture.update(low)
	high_texture.update(high)
	for blend in [0.0, 0.5, 1.0]:
		view.set_surface_fields(low_texture, high_texture, blend)
		var image: Image = await _capture("edge-projection-" + str(blend))
		var location: Vector2i = Vector2i(camera.unproject_position(Vector3(2 - 4 * blend, 0, 0)))
		_check(_energy(image, location, Vector2i(3, 10)) > 5, "The fixed fine contour must project to the current LOD's actual sea edge.")
	fixture.queue_free()
	await process_frame
	print("Coast widths (coverage pixels): ", widths)

func _run() -> void:
	var view = View.new()
	root.add_child(view)
	view.build_paths(_paths([Vector2(2, 2), Vector2(18, 2), Vector2(18, 18), Vector2(2, 18)], true), Vector2(20, 20), 0, Color.WHITE)
	_check(view.segment_count == 4 and view._ribbons.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, "Closed islands must use four connected ribbon segments, not line primitives.")
	var arrays: Array = view._ribbons.mesh.surface_get_arrays(0)
	var last_distance: float = 0
	for uv in arrays[Mesh.ARRAY_TEX_UV]:
		last_distance = maxf(last_distance, uv.x)
	_check(is_equal_approx(last_distance, 64), "Distance along a closed coastline must include the closing segment.")
	view.build_paths(_paths([Vector2(2, 2), Vector2(10, 2), Vector2(2.1, 3)]), Vector2(20, 20), 0, Color.WHITE)
	_check(view.segment_count == 2 and view.bevel_count == 1, "An acute bend needs a bevel, while the cropped path stays open.")
	arrays = view._ribbons.mesh.surface_get_arrays(0)
	var shared_angles: Dictionary = {}
	for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
		var position: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		var angle: float = arrays[Mesh.ARRAY_TEX_UV2][i].y
		_check(not shared_angles.has(position) or is_equal_approx(shared_angles[position], angle), "All vertices at a join must use one shared sea-edge projection direction, including bevels.")
		shared_angles[position] = angle
	for join in arrays[Mesh.ARRAY_TEX_UV2]:
		_check(is_finite(join.x) and join.x <= 2.001, "Join extrusion must stay bounded and never create a sharp spike.")
	view.build_paths(_paths([Vector2(2, 2), Vector2(2, 2), Vector2(10, 2), Vector2(18, 2)]), Vector2(20, 20), 0, Color.WHITE, func(p: Vector2) -> bool: return p.x > 10)
	_check(view.segment_count == 1, "Duplicate points must be safe, and filtering must operate on individual segments.")
	var strait: Array[Dictionary] = _paths([Vector2(9.8, 2), Vector2(9.8, 18)])
	strait.append_array(_paths([Vector2(10.2, 18), Vector2(10.2, 2)]))
	view.build_paths(strait, Vector2(20, 20), 0, Color.WHITE)
	_check(view.path_count == 2 and view.segment_count == 2, "Opposite banks of a narrow strait must never be joined or closed by ribbon construction.")
	view.build_paths([], Vector2(20, 20), 0, Color.WHITE)
	_check(view._ribbons == null, "Empty coast sets must clear old geometry without creating a map frame.")
	view.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await _gpu_fixture()
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	terrain.map_size = Vector2(256, 192)
	terrain.terrain_template = "High Island"
	terrain.regenerate()
	var shore = terrain.geography_view
	_check(shore._ribbons != null and shore._ribbons.is_inside_tree() and shore.segment_count > 0, "Generated terrain must build visible ocean shore ribbons.")
	var mesh_id: int = shore._ribbons.mesh.get_instance_id()
	var geography = terrain.geography.snapshot()
	var builds: int = shore.build_count
	var camera = world.get_node("CameraRig")
	for zoom in [1.0, 3.0, 12.0]:
		camera._zoom = zoom
		camera._apply_zoom()
		terrain.detail._process(1)
		shore._process(0)
		_check(shore._ribbons.visible and shore._ribbons.mesh.get_instance_id() == mesh_id and shore.build_count == builds, "Zoom must retain the same ribbon mesh in both overview and angled views.")
		var level: int = terrain.detail.current_level
		_check(shore._material.get_shader_parameter("height_fine") == terrain.detail.height_textures[level] and is_equal_approx(shore._material.get_shader_parameter("field_blend"), terrain.detail.blend), "Shore draping must consume the actual displayed terrain LOD and morph blend.")
	terrain.apply_climate(terrain.climate_settings.merged({"rainfall_scale": 0.0}, true))
	_check(shore.build_count == builds and shore._ribbons.mesh.get_instance_id() == mesh_id, "Rainfall edits must reuse ocean shoreline geometry.")
	_check(terrain.geography.snapshot() == geography, "Presentation must preserve canonical coast identity and saved geography.")
	for mode in range(1, 6):
		terrain.set_climate_view(mode)
		_check(not shore._ribbons.visible, "Diagnostic views must hide decorative outlines.")
	terrain.set_climate_view(0)
	terrain.set_heightmap_view(true)
	_check(not shore._ribbons.visible, "Show heights must hide decorative outlines.")
	terrain.set_heightmap_view(false)
	_check(shore._ribbons.visible, "Terrain view must restore its outlines.")
	if DisplayServer.get_name() != "headless":
		world.get_node("Interface/Editor")._sync_from_terrain()
		camera._zoom = 1
		camera._apply_zoom()
		await _capture("island-overview")
		var centers: PackedVector3Array = shore._ribbons.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var coast: Vector3 = centers[centers.size() / 2]
		camera.position.x = coast.x
		camera.position.z = coast.z
		camera._zoom = camera._fit_size / 32.0
		camera._apply_zoom()
		terrain.detail._process(1)
		shore._process(0)
		await _capture("island-angled")
	terrain.close_detail_enabled = false
	terrain.regenerate()
	_check(shore._ribbons != null and shore._ribbons.is_inside_tree(), "Disabling detailed terrain must rebuild ribbons for the base surface.")
	_check(shore._material.get_shader_parameter("height_fine").get_size() == Vector2(terrain.sample_size()), "Base-only coast draping must use base heights rather than stale LOD textures.")
	world.queue_free()
	await process_frame
	print("Terrain coastline checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
