extends SceneTree
const Document = preload("res://scripts/storage/terrain_document.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const Library = preload("res://scripts/rendering/terrain_tree_library.gd")
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _capture(name_text: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://.godot/vegetation-" + name_text + ".png")
	return image

func _difference(a: Image, b: Image) -> float:
	var result: float = 0
	for y in range(150, 620, 3):
		for x in range(420, 940, 3):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			result += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return result

func _large_root_fixture() -> void:
	# A renderer check at large coordinates/heights, not a large-map performance test.
	var fixture := Node3D.new()
	root.add_child(fixture)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color.BLACK
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 1
	environment.environment = settings
	fixture.add_child(environment)
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/rendering/vegetation.gdshader")
	material.set_shader_parameter("map_size", Vector2(4096, 2048))
	var low := Image.create(2, 2, false, Image.FORMAT_RF)
	var high := Image.create(2, 2, false, Image.FORMAT_RF)
	for row in range(2):
		low.set_pixel(0, row, Color(-224, 0, 0))
		low.set_pixel(1, row, Color(1824, 0, 0))
		high.set_pixel(0, row, Color(-222, 0, 0))
		high.set_pixel(1, row, Color(1826, 0, 0))
	material.set_shader_parameter("height_coarse", ImageTexture.create_from_image(low))
	material.set_shader_parameter("height_fine", ImageTexture.create_from_image(high))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = Library.mesh_for(0, false)
	multi.instance_count = 1
	var x: float = 1023.7
	multi.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.87), Vector3(x, 40, 0)))
	multi.custom_aabb = AABB(Vector3(x - 2, 0, -2), Vector3(4, 1600, 4))
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = material
	fixture.add_child(node)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4
	camera.near = 0.01
	camera.far = 50
	fixture.add_child(camera)
	camera.current = true
	for blend in [0.0, 0.5, 1.0]:
		material.set_shader_parameter("field_blend", blend)
		var height: float = 800 + x * 0.5 + blend * 2 - 0.015
		camera.position = Vector3(x, height + 12, 12)
		camera.look_at(Vector3(x, height, 0))
		var image: Image = await _capture("large-root-" + str(blend))
		var pixel := Vector2i(camera.unproject_position(Vector3(x, height + 0.65 * 0.87, 0)))
		var energy: float = 0
		for y in range(pixel.y - 10, pixel.y + 11):
			for column in range(pixel.x - 10, pixel.x + 11):
				energy += image.get_pixel(column, y).g
		_check(energy > 20, "Large-coordinate tree roots must follow the displayed height blend using their instance transform.")
	fixture.queue_free()
	await process_frame


func _run() -> void:
	Library.ensure_library()
	if DisplayServer.get_name() != "headless":
		await _large_root_fixture()
	_check(Library.meshes.size() == 10, "Five original tree types must each have detailed and simplified meshes.")
	for kind in range(5):
		_check(Library.mesh_for(kind, true).surface_get_array_len(0) < Library.mesh_for(kind, false).surface_get_array_len(0), "Every tree type must reduce geometry at distance.")
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	terrain.map_size = Vector2(256, 192)
	terrain.terrain_template = "Continents"
	terrain.island_enabled = false
	terrain.regenerate()
	var options: Dictionary = terrain.climate_settings.duplicate()
	options.latitude_center = 25
	options.latitude_span = 35
	options.rainfall_scale = 2
	terrain.apply_climate(options)
	var vegetation = terrain.vegetation_view
	var layout = vegetation.layout
	_check(layout.instances.size() > 20 and layout.instances.size() <= 60000 and layout.candidate_count <= 200000, "Vegetation must be visible but obey bounded placement budgets.")
	_check(vegetation.groups.size() > 1, "Forests must use spatial chunks rather than one world-sized MultiMesh.")
	var snapshot: Array = layout.instances.duplicate(true)
	var source_heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var original_geo: Dictionary = terrain.geography.snapshot()
	var count: int = 0
	for value in layout.counts:
		count += value
	_check(count == layout.instances.size(), "Inspector counts must sum to the actual placement population.")
	for tree in layout.instances:
		var cell: int = tree.cell
		_check(terrain.biomes.canopy[cell] > 0 and terrain.hydrology.ocean[cell] == 0 and terrain.hydrology.river_ids[cell] < 0, "Every tree must belong to suitable non-ocean, non-channel land.")
		var lake: int = terrain.hydrology.lake_ids[cell]
		_check(lake < 0 or not terrain.hydrology.lakes[lake].active, "Trees must stay out of active lake cells.")
		_check(not terrain.hydrology_view.river_near(tree.point, 0.43 * tree.scale), "Tree footprints must clear the actual rounded river ribbons.")
		var point: Vector2 = tree.point / terrain.map_size
		for i in range(3):
			_check(Grid.sample(terrain.detail.height_fields[i], terrain.detail.height_sizes[i], point) > terrain.sea_level * terrain.relief_scale() + 0.04, "Tree roots must remain above water in all three terrain LODs.")
	for corridor in terrain.hydrology_view.river_corridors:
		_check(terrain.hydrology_view.river_near((corridor.a + corridor.b) * 0.5), "The river clearance index must contain every rendered segment midpoint.")
	var builds: int = vegetation.build_count
	var mesh_id: int = terrain.detail.chunks[0].meshes[0].get_instance_id()
	var multi_id: int = vegetation.groups[0].node.multimesh.get_instance_id()
	var rig = world.get_node("CameraRig")
	for zoom in [1, 3, 12]:
		rig._zoom = zoom
		rig._apply_zoom()
		terrain.detail._process(1)
		vegetation._process(0)
		_check(vegetation.build_count == builds and vegetation.groups[0].node.multimesh.get_instance_id() == multi_id and layout.instances == snapshot, "Camera movement must never respawn or rebuild the forest.")
		_check(vegetation._material.get_shader_parameter("height_fine") == terrain.detail.height_textures[terrain.detail.current_level], "Tree bases must follow the current terrain height field.")
	rig._zoom = 1
	rig._apply_zoom()
	vegetation._process(0)
	_check(not vegetation.visible, "Fully zoomed-out overview must hide individual trees.")
	var path := "res://.godot/vegetation-roundtrip.terrain.json"
	_check(Document.save_file(path, terrain).is_empty(), "Vegetated maps must save with the current format.")
	terrain.apply_climate(options.merged({"rainfall_scale": 0.0}, true))
	_check(terrain.vegetation_view.layout.instances.size() < snapshot.size(), "Drying the climate must reduce the forest population.")
	_check(terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh_id and terrain.height_samples == source_heights, "Vegetation updates must preserve terrain geometry.")
	var loaded: Dictionary = Document.load_file(path)
	_check(loaded.ok and Document.apply(terrain, loaded.document).is_empty(), "Vegetated maps must load through the real file pipeline.")
	vegetation = terrain.vegetation_view
	_check(vegetation.layout.instances == snapshot and terrain.geography.snapshot() == original_geo, "JSON reload must exactly reproduce tree types, transforms and tint without changing geography.")
	_check(terrain.cell_info(snapshot[0].cell).tree_count > 0, "The inspector must expose placed trees independently of potential canopy.")
	for mode in range(1, 6):
		terrain.set_climate_view(mode)
		_check(not vegetation.visible, "Climate and biome diagnostics must hide tree decoration.")
	terrain.set_climate_view(0)
	terrain.set_heightmap_view(true)
	_check(not vegetation.visible, "Height inspection must hide trees.")
	terrain.set_heightmap_view(false)
	if DisplayServer.get_name() != "headless":
		world.get_node("Interface/Editor")._sync_from_terrain()
		rig._reset_view()
		await _capture("overview")
		var chosen: Dictionary = snapshot[0]
		var density: int = 0
		for tree in snapshot:
			if vegetation.layout.counts[tree.cell] > density:
				chosen = tree
				density = vegetation.layout.counts[tree.cell]
		var center: Vector2 = chosen.point - terrain.map_size * 0.5
		rig.position.x = center.x
		rig.position.z = center.y
		rig._zoom = rig._fit_size / 18.0
		rig._apply_zoom()
		terrain.detail._process(1)
		vegetation._process(0)
		_check(vegetation.visible and vegetation.fade > 0.99, "Close terrain must show its detailed trees.")
		var forest: Image = await _capture("forest-close")
		vegetation.visible = false
		vegetation.set_process(false)
		var bare: Image = await _capture("forest-hidden")
		_check(_difference(forest, bare) > 10, "The rendered forest must visibly add 3D vegetation.")
		vegetation.set_process(true)
		vegetation._process(0)
		terrain.set_climate_view(2)
		var rain_a: Image = await _capture("rainfall")
		vegetation.visible = false
		vegetation.set_process(false)
		var rain_b: Image = await _capture("rainfall-hidden")
		_check(_difference(rain_a, rain_b) < 0.01, "Tree decoration must not change rainfall diagnostic pixels.")
		vegetation.set_process(true)
		terrain.set_climate_view(0)
	DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	print("Vegetation: %d instances, %d groups, %d candidates, %.1f ms layout" % [vegetation.layout.instances.size(), vegetation.groups.size(), vegetation.layout.candidate_count, vegetation.layout.generation_ms])
	terrain.close_detail_enabled = false
	terrain.regenerate()
	_check(terrain.vegetation_view.layout != null, "Base-only terrain must still support vegetation.")
	world.queue_free()
	await process_frame
	print("Terrain vegetation checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
