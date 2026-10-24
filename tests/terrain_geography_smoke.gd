extends SceneTree
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Geography = preload("res://scripts/domain/terrain_geography.gd")
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
	var graph = Graph.new()
	graph.generate(Vector2(256, 192), 1000, "geography")
	for kind in ["ocean", "land", "island", "small_island", "lake", "nested", "cropped", "strait"]:
		for cell in range(graph.count):
			var uv: Vector2 = graph.points[cell] / graph.map_size
			var radius: float = (uv - Vector2(0.5, 0.5)).length()
			var land: bool = false
			match kind:
				"land": land = true
				"island": land = radius < 0.25
				"small_island": land = radius < 0.12
				"lake": land = radius > 0.20
				"nested": land = (radius > 0.17 and radius < 0.36) or radius < 0.065
				"cropped": land = uv.x < 0.5
				"strait": land = cell % graph.columns not in [graph.columns / 2, graph.columns / 2 + 1]
			graph.heights[cell] = 60 if land else 0
		graph.invalidate_display()
		var original: PackedByteArray = graph.heights.duplicate()
		var geography = Geography.new()
		geography.generate(graph, 1)
		_check(graph.heights == original, "Geography must not change source heights.")
		_check(Geography.validate_cache(geography.snapshot(), graph.snapshot(), graph.map_size, 1).is_empty(), kind + " must create a valid portable geography snapshot.")
		var counts := {"landmass": 0, "island": 0, "open_water": 0, "inland_water": 0}
		var area: float = 0.0
		var examined: int = 0
		for feature in geography.features:
			counts[feature.kind] += 1
			area += feature.area
			examined += feature.cell_count
		_check(examined == graph.count and absf(area / (256.0 * 192.0) - 1.0) < 0.002, "Every cell and its area must belong to exactly one feature.")
		for cell in range(graph.count):
			var land: bool = graph.heights[cell] >= 20
			_check((geography.features[geography.feature_ids[cell]].kind in ["landmass", "island"]) == land, "Feature types must agree with cell heights.")
			var coastal: bool = false
			var best: float = INF
			for neighbor in graph.neighbors[cell]:
				if land == (graph.heights[neighbor] >= 20):
					_check(geography.feature_ids[cell] == geography.feature_ids[neighbor], "Adjacent cells of the same type must share one component.")
				else:
					coastal = true
				if geography.distance_to_coast[neighbor] >= 0.0:
					best = minf(best, geography.distance_to_coast[neighbor] + graph.points[cell].distance_to(graph.points[neighbor]))
			_check((geography.coastal[cell] != 0) == coastal, "Every coastal cell must have an opposite-type neighbor.")
			if coastal:
				_check(geography.distance_to_coast[cell] == 0.0, "Coastal cells must be distance seeds.")
			elif is_finite(best):
				_check(absf(geography.distance_to_coast[cell] - best) < 0.01, "Coast distance must satisfy the shortest-path recurrence.")
			else:
				_check(geography.distance_to_coast[cell] == -1.0, "A world with no coastline must report no distance, not a guessed zero.")
		var holes: int = 0
		var rings: int = 0
		var open_paths: int = 0
		for coast in geography.coastlines:
			holes += int(coast.hole)
			rings += int(coast.closed)
			open_paths += int(not coast.closed)
			for point in coast.points:
				_check(absf(Grid.sample(geography.display_heights, geography.contour_size, point / graph.map_size) - 0.2) < 0.0001, "Every displayed shoreline vertex must lie on the fixed sea-level contour.")
		match kind:
			"ocean": _check(counts.open_water == 1 and geography.coastlines.is_empty(), "An all-water map must be one open water body without invented shorelines.")
			"land": _check(counts.landmass == 1 and geography.coastlines.is_empty(), "An all-land map must not draw its rectangular frame as a coast.")
			"island": _check(counts.landmass == 1 and counts.open_water == 1 and rings == 1 and holes == 0, "An island must have one positive outer shoreline ring.")
			"small_island": _check(counts.island == 1 and counts.landmass == 0 and counts.open_water == 1 and rings == 1, "A small enclosed land component must be labelled Island, retaining its coast ring.")
			"lake": _check(counts.inland_water == 1 and counts.open_water == 0 and holes == 1, "An enclosed low-water area must be an inland candidate with a hole contour.")
			"nested": _check(counts.landmass == 1 and counts.island == 1 and counts.open_water == 1 and counts.inland_water == 1 and rings == 3 and holes == 1, "Nested islands and water holes must remain distinct and correctly oriented.")
			"cropped": _check(open_paths > 0 and rings == 0, "A cropped coast must remain open at the map boundary.")
			"strait": _check(counts.open_water == 1 and counts.landmass == 2, "A narrow open strait must connect its water and separate the land.")
		var repeat = Geography.new()
		repeat.generate(graph, 1)
		_check(geography.snapshot() == repeat.snapshot(), "Identical graph inputs must reproduce IDs, distances and contours exactly.")
		print(kind, ": ", counts, ", ", geography.coastlines.size(), " shoreline paths, %.2f ms" % geography.generation_ms)
	_check(Geography.land_kind(999.0, false, 10000.0) == "island" and Geography.land_kind(1000.0, false, 10000.0) == "landmass", "The large-landmass threshold must be inclusive at 10% of map area.")
	_check(Geography.land_kind(1.0, true, 10000.0) == "landmass", "Border-touching land must not be called an island on a cropped map.")
	_check(Geography.land_kind(999.0 * 4, false, 40000.0) == "island", "Land size classification must scale with map area, not cell count.")
	# Exercise real terrain regeneration, the inspector, files and the LOD camera.
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	terrain.auto_density = false
	terrain.graph_points = 1000
	terrain.map_size = Vector2(256, 192)
	terrain.resolution = 128
	terrain.terrain_template = "High Island"
	terrain.regenerate()
	var saved: Dictionary = Document.capture(terrain)
	_check(saved.version == Document.VERSION and Document.validate(saved).is_empty(), "Current terrain files must include validated geography data.")
	var before: Dictionary = terrain.geography.snapshot()
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var path := "res://.godot/geography-roundtrip.terrain.json"
	_check(Document.save_file(path, terrain).is_empty(), "Geographic maps must save.")
	var loaded: Dictionary = Document.load_file(path)
	var load_error: String = Document.apply(terrain, loaded.document) if loaded.ok else loaded.error
	_check(load_error.is_empty(), "Saved geographic maps must load through the public file pipeline: " + load_error)
	_check(terrain.geography.snapshot() == before and terrain.height_samples == heights, "Loading must preserve geographic identities and the exact saved height samples.")
	var bad: Dictionary = saved.duplicate(true)
	bad.geography.feature_ids[0] = -1
	_check(not Document.apply(terrain, bad).is_empty() and terrain.geography.snapshot() == before, "Malformed geographic cache data must be rejected before changing terrain.")
	bad = saved.duplicate(true)
	bad.geography.source_hash = "stale"
	_check(not Document.validate(bad).is_empty(), "Stale geography must not validate against a different graph.")
	# Source geometry owns the facts even when a structurally valid cache is edited.
	bad = saved.duplicate(true)
	bad.geography.features[0].area *= 0.9999
	_check(Document.apply(terrain, bad).is_empty() and terrain.geography.snapshot() == before, "Loading must rebuild derived facts from the graph instead of trusting edited cache measurements.")
	bad = saved.duplicate(true)
	bad.geography.contour_size[0] += 0.5
	_check(not Document.validate(bad).is_empty(), "Fractional contour dimensions must not be silently truncated during cache parsing.")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.geography.version = 1
	for feature in legacy.geography.features:
		if feature.kind == "island":
			feature.kind = "landmass"
	_check(Document.apply(terrain, legacy).is_empty() and terrain.geography.snapshot() == before, "Old geographic caches must load and gain island labels without changing the original map.")
	var old: Dictionary = saved.duplicate(true)
	old.version = 4
	old.erase("geography")
	_check(Document.apply(terrain, old).is_empty() and terrain.geography.snapshot() == before, "Version 4 graph saves must gain geography without changing their heights.")
	var cache = terrain.geography
	var camera = world.get_node("CameraRig")
	var shore_mesh: int = terrain.geography_view._lines.mesh.get_instance_id()
	for zoom in [1.0, 5.0, 20.0]:
		camera._zoom = zoom
		camera._apply_zoom()
		terrain.detail._process(1.0)
		_check(terrain.geography == cache and terrain.geography.snapshot() == before, "Zoom and LOD must never regenerate geographic identities or shorelines.")
		_check(terrain.geography_view._lines.mesh.get_instance_id() == shore_mesh and terrain.geography_view._lines.visible == (zoom == 1.0), "Overview shores must fade by visibility without rebuilding their mesh.")
	var info: Dictionary = terrain.cell_info(0)
	_check(info.has("feature_kind") and info.has("coast_distance") and info.has("depth"), "The cell inspector must consume generated geography facts.")
	DirAccess.remove_absolute(path)
	world.queue_free()
	await process_frame
	print("Terrain geography checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
