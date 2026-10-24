extends SceneTree
## Optional GPU captures of all prebuilt levels and a shadow coverage comparison.
const Document = preload("res://scripts/storage/terrain_document.gd")


func _initialize() -> void:
	_run.call_deferred()


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run this visual check with a GPU renderer.")
		quit(1)
		return
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var camera = world.get_node("CameraRig")
	var sun = world.get_node("Sun")
	var cached: Dictionary = Document.load_file("res://.godot/strategy-preview.terrain.json")
	if cached.has("error"):
		push_error(cached.error)
		quit(1)
		return
	var error: String = Document.apply(terrain, cached.document)
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	var geography_error: String = Document.save_file("res://.godot/geography-world.terrain.json", terrain)
	if not geography_error.is_empty():
		push_error(geography_error)
		quit(1)
		return
	var geographic_file: Dictionary = Document.load_file("res://.godot/geography-world.terrain.json")
	if not geographic_file.ok:
		push_error(geographic_file.error)
		quit(1)
		return
	print("Geography: ", terrain.geography.features.size(), " features, ", terrain.geography.coastlines.size(), " shoreline paths, %.2f ms, saved %.2f MiB" % [terrain.geography.generation_ms, FileAccess.get_file_as_bytes("res://.godot/geography-world.terrain.json").size() / 1048576.0])
	world.get_node("Interface/Editor")._sync_from_terrain()
	var mesh_ids: Array[int] = []
	for mesh in terrain.detail.chunks[0].meshes:
		mesh_ids.append(mesh.get_instance_id())
	camera._reset_view()
	if not is_equal_approx(camera.rotation_degrees.x, -90.0) or not is_equal_approx(terrain.overview_blend, 1.0) or sun.shadow_enabled:
		push_error("Full overview must be flat and exactly overhead.")
		quit(1)
		return
	terrain.detail.set_detail(0.0)
	await _capture("res://.godot/lod-overview.png")
	var inspected: int = 0
	for feature in terrain.geography.features:
		if feature.kind == "inland_water" and feature.cell_count > 4:
			inspected = feature.first_cell
			break
	var site: Vector2 = terrain.graph.points[inspected] / terrain.map_size
	var location: Vector2 = (site - Vector2(0.5, 0.5)) * terrain.map_size
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera._camera.unproject_position(Vector3(location.x, terrain.surface_height(site), location.y))
	world.get_node("Interface/Editor")._unhandled_input(click)
	if not world.get_node("Interface/Editor")._cell_label.text.contains("Feature area:"):
		push_error("Clicking the map did not show geographic feature data.")
		quit(1)
		return
	await _capture("res://.godot/geography-inspector.png")
	var point := Vector2(0.70, 0.37)
	var xz: Vector2 = (point - Vector2(0.5, 0.5)) * terrain.map_size
	camera.position = Vector3(xz.x, terrain.surface_height(point), xz.y)
	camera._zoom = 16.0
	camera._apply_zoom()
	await create_timer(0.7).timeout
	await _capture("res://.godot/lod-middle.png")
	camera._zoom = 100.0
	camera._apply_zoom()
	await create_timer(0.7).timeout
	await _capture("res://.godot/lod-close.png")
	# Compare the same terrain/camera projection against the preceding broad
	# depth range and split mode; this isolates coverage/mode rather than AA.
	var original_distance: float = camera._camera.position.z
	var original_far: float = camera._camera.far
	sun.directional_shadow_mode = 2
	sun.shadow_blur = 1.0
	camera._camera.position.z = maxf(terrain.map_size.x, terrain.map_size.y) * 1.5 + (terrain.height_bounds().y - terrain.height_bounds().x) * 2.0
	camera._camera.far = camera._camera.position.z + maxf(terrain.map_size.x, terrain.map_size.y) * 4.0
	sun.directional_shadow_max_distance = camera._camera.far
	await _capture("res://.godot/shadows-wide-frustum.png")
	sun.directional_shadow_mode = 0
	sun.shadow_blur = 1.5
	camera._camera.position.z = original_distance
	camera._camera.far = original_far
	sun.directional_shadow_max_distance = original_far
	await _capture("res://.godot/shadows-tight-frustum.png")
	for i in range(3):
		if terrain.detail.chunks[0].meshes[i].get_instance_id() != mesh_ids[i]:
			push_error("Visual navigation rebuilt a mesh.")
			quit(1)
			return
	print("Visual LOD: ", terrain.detail.chunks.size(), " chunks, 3 cached levels, %.2f ms generation, near %.1f far %.1f" % [terrain.detail.build_ms, camera._camera.near, original_far])
	world.queue_free()
	await process_frame
	quit()
