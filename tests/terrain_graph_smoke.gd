extends SceneTree
## End-to-end cell data, map/display independence, zoom, picking and density.
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
	var editor = world.get_node("Interface/Editor")
	var camera = world.get_node("CameraRig")
	terrain.terrain_template = "High Island"
	terrain.map_seed = "brenden-legacy"
	terrain.graph_points = 1000
	terrain.resolution = 128
	terrain.map_size = Vector2(1024, 512)
	terrain.regenerate()
	var extent: Vector2 = terrain.display_size()
	var span: float = terrain._sample_max - terrain._sample_min
	var raw: PackedByteArray = terrain.graph.heights.duplicate()
	var graph_identity: int = terrain.graph.get_instance_id()
	terrain.resolution = 256
	terrain.regenerate()
	_check(terrain.graph.get_instance_id() == graph_identity and terrain.graph.heights == raw, "Mesh refinement must reuse the graph and preserve authoritative cell data.")
	_check(terrain.graph.uncovered_samples == 0, "The normal map boundary must cover every mesh sample.")
	terrain.map_size *= 2.0
	terrain.regenerate()
	_check(terrain.display_size() == extent * 2.0, "Increasing map dimensions must enlarge the actual 3D footprint.")
	_check(terrain._sample_max - terrain._sample_min >= span * 0.75, "Increasing logical size must not flatten relative relief.")
	var area: float = 0.0
	var degrees: Dictionary = {}
	for cell in range(terrain.graph.count):
		var info: Dictionary = terrain.cell_info(cell)
		_check(info.height == terrain.graph.heights[cell] and info.land == (info.height >= 20), "Cell inspector must use the graph's authoritative land data.")
		_check(info.area > 0.0, "Each real Voronoi cell must have positive clipped area.")
		area += info.area
		degrees[info.neighbor_count] = true
		for neighbor in terrain.graph.neighbors[cell]:
			_check(cell in terrain.graph.neighbors[neighbor], "Voronoi adjacency must be reciprocal.")
	_check(degrees.size() > 3, "The graph must have irregular Voronoi connectivity, not eight fixed grid neighbors.")
	_check(absf(area / (terrain.map_size.x * terrain.map_size.y) - 1.0) < 0.002, "Clipped Voronoi cells must cover the logical map.")
	var info: Dictionary = terrain.pick_cell(Vector3(0, 10000, 0), Vector3.DOWN)
	_check(not info.is_empty() and info.id == terrain.graph.nearest_cell(terrain.map_size * 0.5), "Picking must follow the visible surface to the correct Voronoi cell.")
	camera._reset_view()
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in range(100):
		camera._unhandled_input(wheel)
	_check(is_equal_approx(camera._camera.size, camera.closest_view_size), "Maximum zoom must reach the fixed closest-view size.")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for i in range(100):
		camera._unhandled_input(wheel)
	_check(is_equal_approx(camera._zoom, 1.0), "Default minimum relative zoom must be 1.")
	await process_frame
	var view_camera: Camera3D = world.get_node("CameraRig/Camera3D")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = view_camera.unproject_position(Vector3(0, maxf(terrain.surface_height(Vector2(0.5, 0.5)), terrain.sea_level * terrain.relief_scale()), 0))
	editor._unhandled_input(click)
	_check(editor._cell_label.text.begins_with("CELL ") and editor._cell_label.text.contains("neighbors"), "Runtime map clicks must display terrain-only cell data.")
	var document: Dictionary = Document.capture(terrain)
	var saved_heights: PackedByteArray = terrain.graph.heights.duplicate()
	var saved_points: PackedVector2Array = terrain.graph.points.duplicate()
	var saved_triangles: PackedInt32Array = terrain.graph.triangles.duplicate()
	terrain.map_seed = "different"
	terrain.regenerate()
	_check(Document.apply(terrain, document).is_empty(), "The full graph document must apply successfully.")
	_check(terrain.graph.heights == saved_heights and terrain.graph.points == saved_points and terrain.graph.triangles == saved_triangles, "Saving must preserve exact cell data and geometry.")
	var bad: Dictionary = Document.capture(terrain)
	bad.graph.triangles[0] = bad.graph.points.size()
	var previous: PackedFloat32Array = terrain.height_samples.duplicate()
	_check(not Document.apply(terrain, bad).is_empty() and terrain.height_samples == previous, "Malformed graph indices must be rejected before mutation.")
	terrain.graph_points = 100000
	terrain.map_size = Vector2(1536, 768)
	terrain.regenerate()
	_check(terrain.graph.count > 90000 and terrain.graph.count < 110000, "Maximum requested density must build a real graph near 100,000 cells.")
	print("100,000 requested points, ", terrain.graph.count, " actual cells, 256 mesh: %.3f s" % (terrain.generation_ms / 1000.0))
	world.queue_free()
	await process_frame
	print("Voronoi editor checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
