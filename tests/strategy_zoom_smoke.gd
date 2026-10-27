extends SceneTree
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var camera = world.get_node("CameraRig")
	terrain.close_detail_enabled = false
	terrain.auto_density = false
	terrain.graph_points = 1000
	terrain.resolution = 128
	var image := Image.create(2, 2, false, Image.FORMAT_RF)
	image.fill(Color(0.47, 0.47, 0.47))
	terrain.heightmap_texture = ImageTexture.create_from_image(image)
	terrain.map_size = Vector2(256, 256)
	terrain.regenerate()
	var small: AABB = terrain.get_node("Surface").mesh.get_aabb()
	camera._reset_view()
	camera._zoom = camera.max_zoom
	camera._apply_zoom()
	var small_zoom: float = camera._zoom
	var close_depth: float = camera._camera.far
	_check(is_equal_approx(camera._camera.size, 8.0), "Small maps must support the absolute close-up view size.")
	camera._reset_view()
	_check(camera._camera.far > close_depth * 2.0, "The shadow frustum must tighten for close views rather than cover the full world depth.")
	terrain.map_size = Vector2(1024, 1024)
	terrain.regenerate()
	var large: AABB = terrain.get_node("Surface").mesh.get_aabb()
	_check(is_equal_approx(large.size.x / small.size.x, 4.0), "A 1024-wide map must be physically four times wider than a 256-wide map.")
	_check(is_equal_approx(large.position.y / small.position.y, 4.0), "Relief must scale with the world to preserve its relative shape.")
	camera._reset_view()
	camera._zoom = camera.max_zoom
	camera._apply_zoom()
	_check(is_equal_approx(camera._camera.size, 8.0) and camera._zoom > small_zoom * 3.9, "Large maps must zoom much further relative to their overview, while reaching the same local scale.")
	terrain.auto_density = true
	terrain.graph_points = 10000
	_check(terrain.effective_graph_points() == 10000, "1024 squared uses the requested reference density.")
	terrain.map_size = Vector2(2048, 2048)
	_check(terrain.effective_graph_points() == 40000, "Doubling both dimensions must request four times the cell data.")
	terrain.map_size = Vector2(8192, 8192)
	_check(terrain.effective_graph_points() == 100000, "Automatic density must respect the cell budget.")
	terrain.auto_density = false
	terrain.graph_points = 1000
	terrain.map_size = Vector2(1024, 1024)
	terrain.heightmap_texture = null
	terrain.terrain_template = "High Island"
	terrain.resolution = 64
	terrain.regenerate()
	terrain.close_detail_enabled = true
	terrain.micro_detail_strength = 0.0
	var raw: PackedByteArray = terrain.graph.heights.duplicate()
	var base: PackedFloat32Array = terrain.height_samples.duplicate()
	terrain.regenerate()
	var lod = terrain.detail
	_check(lod.active and not terrain.get_node("Surface").visible, "Prebuilt chunks must replace the base preview at runtime.")
	_check(lod.chunks.size() == lod.chunk_count.x * lod.chunk_count.y, "Every map chunk must be built before zooming.")
	for chunk in lod.chunks:
		_check(chunk.meshes.size() == 3 and chunk.fields.size() == 3, "Each chunk must have exactly three prebuilt levels.")
		for level in range(2):
			var small_size: Vector2i = chunk.sizes[level]
			var high_size: Vector2i = chunk.sizes[2]
			var stride: int = (high_size.x - 1) / (small_size.x - 1)
			for y in range(small_size.y):
				for x in range(small_size.x):
					_check(chunk.fields[level][y * small_size.x + x] == chunk.fields[2][y * stride * high_size.x + x * stride], "All levels must be subsets of one fixed heightfield.")
	# Adjacent chunks share every boundary height at every level.
	for y in range(lod.chunk_count.y):
		for x in range(lod.chunk_count.x - 1):
			var left: Dictionary = lod.chunks[y * lod.chunk_count.x + x]
			var right: Dictionary = lod.chunks[y * lod.chunk_count.x + x + 1]
			for level in range(3):
				var size: Vector2i = left.sizes[level]
				var left_arrays: Array = left.meshes[level].surface_get_arrays(0)
				var right_arrays: Array = right.meshes[level].surface_get_arrays(0)
				for row in range(size.y):
					_check(left_arrays[Mesh.ARRAY_NORMAL][row * size.x + size.x - 1].is_equal_approx(right_arrays[Mesh.ARRAY_NORMAL][row * size.x]), "Chunk edge normals must share the global field to prevent lighting seams.")
					_check(left.fields[level][row * size.x + size.x - 1] == right.fields[level][row * size.x], "Chunk edges must match without cracks.")
	for y in range(lod.chunk_count.y - 1):
		for x in range(lod.chunk_count.x):
			var top: Dictionary = lod.chunks[y * lod.chunk_count.x + x]
			var bottom: Dictionary = lod.chunks[(y + 1) * lod.chunk_count.x + x]
			for level in range(3):
				var size: Vector2i = top.sizes[level]
				var ta: Array = top.meshes[level].surface_get_arrays(0)
				var ba: Array = bottom.meshes[level].surface_get_arrays(0)
				for col in range(size.x):
					_check(top.fields[level][(size.y - 1) * size.x + col] == bottom.fields[level][col] and ta[Mesh.ARRAY_NORMAL][(size.y - 1) * size.x + col].is_equal_approx(ba[Mesh.ARRAY_NORMAL][col]), "North/south chunk boundaries must share heights and lighting.")
	var built: int = lod.build_count
	var instances: Array[int] = []
	for mesh in lod.chunks[0].meshes:
		instances.append(mesh.get_instance_id())
	lod.set_detail(1.0)
	var medium_height: float = terrain.surface_height(Vector2(0.43, 0.41))
	lod.set_detail(1.00001)
	_check(absf(terrain.surface_height(Vector2(0.43, 0.41)) - medium_height) < 0.001, "Geometry transitions must be continuous at the middle level.")
	lod.set_detail(1.5)
	var uv_test := Vector2(0.43, 0.41)
	var coord_test := uv_test * Vector2(lod.chunk_count)
	var tile: Dictionary = lod.chunks[int(coord_test.y) * lod.chunk_count.x + int(coord_test.x)]
	var local_uv := coord_test - coord_test.floor()
	var arrays: Array = tile.meshes[2].surface_get_arrays(0)
	var fine := PackedFloat32Array()
	var parent := PackedFloat32Array()
	for vertex in arrays[Mesh.ARRAY_VERTEX]:
		fine.append(vertex.y)
	for value in arrays[Mesh.ARRAY_TEX_UV2]:
		parent.append(value.x)
	var rendered: float = lerpf(Grid.sample(parent, tile.sizes[2], local_uv), Grid.sample(fine, tile.sizes[2], local_uv), 0.5)
	_check(is_equal_approx(terrain.surface_height(uv_test), rendered), "Picking must match the actual vertex morph attributes uploaded to the GPU.")
	var mixed: float = terrain.surface_height(Vector2(0.43, 0.41))
	lod.set_detail(2.0)
	_check(is_equal_approx(mixed, (medium_height + terrain.surface_height(Vector2(0.43, 0.41))) * 0.5), "Picking must follow the same morph as rendered geometry.")
	for level in range(3):
		_check(lod.chunks[0].meshes[level].get_instance_id() == instances[level], "Zoom must reuse prebuilt mesh resources.")
	_check(lod.build_count == built and terrain.graph.heights == raw and terrain.height_samples == base, "Changing levels must not rebuild geometry or mutate terrain data.")
	camera._camera.size = 1024 * 0.6
	lod.target_level = 0
	lod._process(1.0)
	_check(lod.target_level == 0, "The overview must retain the low level before its entry threshold.")
	camera._camera.size = 1024 * 0.54
	lod._process(1.0)
	_check(lod.target_level == 1, "Zooming past the first threshold must select the middle level.")
	camera._camera.size = 1024 * 0.6
	lod._process(1.0)
	_check(lod.target_level == 1, "The middle level must remain stable inside the hysteresis band.")
	camera._camera.size = 1024 * 0.12
	lod._process(1.0)
	_check(lod.target_level == 2 and lod.build_count == built, "The closest level must already exist when selected.")
	terrain.set_heightmap_view(true)
	_check(lod.build_count == built and lod.active, "Grayscale view must retain cached terrain meshes.")
	terrain.set_heightmap_view(false)
	print("Fixed LOD: ", lod.chunks.size(), " chunks, 3 levels each, %.2f ms prebuild" % lod.build_ms)
	# Tight shadow coverage must still contain every projected high-field vertex.
	# Check overview, close-up, pan, orbit and a low manual tilt.
	for view in [[1.0, 0.0, 55.0], [10.0, 0.0, 55.0], [100.0, 35.0, 30.0], [80.0, -60.0, 70.0]]:
		camera._yaw = view[1]
		camera._pitch = view[2]
		camera.position = Vector3(45, terrain.surface_height(Vector2(0.54, 0.48)), -20)
		camera._zoom = view[0]
		camera._apply_zoom()
		var axis: Vector3 = camera._camera.global_basis.z
		var right: Vector3 = camera._camera.global_basis.x
		var up: Vector3 = camera._camera.global_basis.y
		var viewport_size: Vector2 = root.get_visible_rect().size
		var half_width: float = camera._camera.size * viewport_size.x / viewport_size.y * 0.5 + absf(camera._camera.h_offset)
		var visible: int = 0
		for y in range(lod.field_size.y):
			for x in range(lod.field_size.x):
				var xz: Vector2 = (Vector2(x, y) / Vector2(lod.field_size - Vector2i.ONE) - Vector2(0.5, 0.5)) * terrain.map_size
				var world_point: Vector3 = terrain.to_global(Vector3(xz.x, lod.field_heights[y * lod.field_size.x + x], xz.y))
				var offset: Vector3 = world_point - camera.global_position
				if absf(offset.dot(right)) <= half_width and absf(offset.dot(up)) <= camera._camera.size * 0.5:
					visible += 1
					var depth: float = -(world_point - camera._camera.global_position).dot(axis)
					_check(depth >= camera._camera.near - 0.01 and depth <= camera._camera.far + 0.01, "Tighter shadow coverage must not clip projected terrain after zoom, pan or tilt.")
		_check(visible > 0, "Camera coverage checks must actually examine visible terrain.")
	var saved: Dictionary = Document.capture(terrain)
	_check(Document.validate(saved).is_empty() and Document.apply(terrain, saved).is_empty(), "Current terrain files must save and restore detail/density settings.")
	var old: Dictionary = saved.duplicate(true)
	old.version = 3
	old.generator_version = 3
	for key in ["auto_density", "close_detail_enabled", "close_detail_resolution", "micro_detail_strength"]:
		old.settings.erase(key)
	_check(Document.apply(terrain, old).is_empty() and not terrain.auto_density, "Version 3 saves must retain their explicit point count.")
	# Anchor to the actual displayed mountain surface, not the buried source height.
	var focus := Vector3(0, terrain.visible_surface_height(Vector2(0.5, 0.5)), 0)
	camera._reset_view()
	var cursor: Vector2 = camera._camera.unproject_position(focus)
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = cursor
	for i in range(10):
		camera._unhandled_input(wheel)
	_check(camera._camera.unproject_position(focus).distance_to(cursor) < 1.0, "Zooming must keep the terrain under the cursor anchored.")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		terrain.auto_density = true
		terrain.graph_points = 10000
		terrain.map_size = Vector2(4096, 2048)
		terrain.terrain_template = "World heightmap"
		terrain.resolution = 512
		terrain.micro_detail_strength = 0.15
		terrain.elevation = 8.0
		terrain.regenerate()
		world.get_node("Interface/Editor")._sync_from_terrain()
		Document.save_file("res://.godot/strategy-preview.terrain.json", terrain)
		camera._reset_view()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/strategy-world-overview.png")
		var selected: int = 0
		var best: float = INF
		for cell in range(terrain.graph.count):
			if terrain.graph.heights[cell] < 25 or terrain.graph.heights[cell] > 60:
				continue
			var spread: int = 0
			for neighbor in terrain.graph.neighbors[cell]:
				spread = maxi(spread, absi(terrain.graph.heights[cell] - terrain.graph.heights[neighbor]))
			if spread > 3:
				continue
			var distance: float = terrain.graph.points[cell].distance_squared_to(terrain.map_size * Vector2(0.55, 0.55))
			if distance < best:
				best = distance
				selected = cell
		var uv: Vector2 = terrain.graph.points[selected] / terrain.map_size
		var xz: Vector2 = (uv - Vector2(0.5, 0.5)) * terrain.map_size
		camera.position = Vector3(xz.x, terrain.base_surface_height(uv), xz.y)
		camera._zoom = camera.max_zoom
		camera._apply_zoom()
		await process_frame
		await create_timer(0.7).timeout
		_check(terrain.detail.active and terrain.detail.target_level == 2, "Deep zoom must select the prebuilt highest level.")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/strategy-world-close.png")
		print("World 4096 x 2048: ", terrain.graph.count, " cells, zoom x%.1f, local span %.1f, prebuild %.2f ms" % [camera._zoom, camera._camera.size, terrain.detail.build_ms])
	world.queue_free()
	await process_frame
	print("Strategy zoom checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
