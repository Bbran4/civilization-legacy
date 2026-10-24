extends RefCounted
## Owns geographic components, coast distance and fixed display shoreline contours.
## Heights stay authoritative; this stage never edits them or simulates lake outlets.

const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const VERSION: int = 2
const LARGE_LAND_FRACTION: float = 0.10
const SEA_DATUM: int = 20
var source_hash: String = ""
var map_size := Vector2.ZERO
var feature_ids := PackedInt32Array()
var coastal := PackedByteArray()
var distance_to_coast := PackedFloat32Array()
var depth := PackedByteArray()
var features: Array[Dictionary] = []
var coastlines: Array[Dictionary] = []
var contour_size := Vector2i.ZERO
var display_heights := PackedFloat32Array()
var discarded_contours: int = 0
var generation_ms: float = 0.0
var _heap: Array = []
var _nodes := PackedVector2Array()
var _node_ids: Dictionary = {}
var _next: Dictionary = {}
var _incoming: Dictionary = {}
var _visited := PackedByteArray()


func generate(graph: RefCounted, smoothing: int) -> void:
	var started: int = Time.get_ticks_usec()
	map_size = graph.map_size
	source_hash = graph.source_fingerprint(smoothing)
	feature_ids.resize(graph.count)
	feature_ids.fill(-1)
	coastal.resize(graph.count)
	coastal.fill(0)
	depth.resize(graph.count)
	features.clear()
	for cell in range(graph.count):
		depth[cell] = maxi(0, SEA_DATUM - graph.heights[cell])
		var land: bool = graph.heights[cell] >= SEA_DATUM
		for neighbor in graph.neighbors[cell]:
			if land != (graph.heights[neighbor] >= SEA_DATUM):
				coastal[cell] = 1
				break
		if feature_ids[cell] != -1:
			continue
		var id: int = features.size()
		var queue: Array[int] = [cell]
		feature_ids[cell] = id
		var cursor: int = 0
		var area: float = 0.0
		var border: bool = false
		while cursor < queue.size():
			var member: int = queue[cursor]
			cursor += 1
			area += graph.cell_area(member)
			border = border or graph.touches_border(member)
			for neighbor in graph.neighbors[member]:
				if feature_ids[neighbor] == -1 and land == (graph.heights[neighbor] >= SEA_DATUM):
					feature_ids[neighbor] = id
					queue.append(neighbor)
		features.append({"id": id, "first_cell": cell, "kind": land_kind(area, border, map_size.x * map_size.y) if land else ("open_water" if border else "inland_water"), "cell_count": queue.size(), "area": area, "touches_border": border})
	_distances(graph)
	# Display contours have a fixed, geography-owned sampling budget, not a
	# camera/LOD resolution. Their values use the same continuous display field.
	contour_size = Grid.sample_size_for(map_size, clampi(maxi(graph.columns, graph.rows) * 2, 32, 512))
	display_heights = graph.rasterize(contour_size, smoothing)
	_contours()
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0


static func land_kind(area: float, border: bool, map_area: float) -> String:
	# A crop cannot establish that a component is surrounded by water.
	return "landmass" if border or area >= map_area * LARGE_LAND_FRACTION else "island"


func _distances(graph: RefCounted) -> void:
	var distances := PackedFloat64Array()
	distances.resize(graph.count)
	distances.fill(INF)
	_heap.clear()
	for cell in range(graph.count):
		if coastal[cell] != 0:
			distances[cell] = 0.0
			_push([0.0, cell])
	while not _heap.is_empty():
		var entry: Array = _pop()
		var cell: int = entry[1]
		if entry[0] > distances[cell]:
			continue
		for neighbor in graph.neighbors[cell]:
			var candidate: float = distances[cell] + graph.points[cell].distance_to(graph.points[neighbor])
			if candidate < distances[neighbor]:
				distances[neighbor] = candidate
				_push([candidate, neighbor])
	distance_to_coast.resize(graph.count)
	for cell in range(graph.count):
		distance_to_coast[cell] = distances[cell] if is_finite(distances[cell]) else -1.0


static func _less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


func _push(entry: Array) -> void:
	_heap.append(entry)
	var index: int = _heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if not _less(entry, _heap[parent]):
			break
		_heap[index] = _heap[parent]
		index = parent
	_heap[index] = entry


func _pop() -> Array:
	var first: Array = _heap[0]
	var last: Array = _heap.pop_back()
	if not _heap.is_empty():
		var index: int = 0
		while index * 2 + 1 < _heap.size():
			var child: int = index * 2 + 1
			if child + 1 < _heap.size() and _less(_heap[child + 1], _heap[child]):
				child += 1
			if not _less(_heap[child], last):
				break
			_heap[index] = _heap[child]
			index = child
		_heap[index] = last
	return first


func _contours() -> void:
	coastlines.clear()
	discarded_contours = 0
	_nodes.clear()
	_node_ids.clear()
	_next.clear()
	_incoming.clear()
	var width: int = contour_size.x
	for y in range(contour_size.y - 1):
		for x in range(width - 1):
			var a: int = y * width + x
			_triangle(a, a + 1, a + width)
			_triangle(a + 1, a + width + 1, a + width)
	_visited = PackedByteArray()
	_visited.resize(_nodes.size())
	# Open shores meet the cropped map boundary; never close them with a fake
	# coastline along the rectangular frame. Trace them before closed rings.
	for node in range(_nodes.size()):
		if _next.has(node) and not _incoming.has(node) and _visited[node] == 0:
			_trace(node)
	for node in range(_nodes.size()):
		if _next.has(node) and _visited[node] == 0:
			_trace(node)
	_nodes.clear()
	_node_ids.clear()
	_next.clear()
	_incoming.clear()
	_visited.clear()


func _triangle(a: int, b: int, c: int) -> void:
	var la: bool = display_heights[a] >= 0.2
	var lb: bool = display_heights[b] >= 0.2
	var lc: bool = display_heights[c] >= 0.2
	if la == lb and lb == lc:
		return
	var ids: Array[int] = [a, b, c]
	var land: Array[bool] = [la, lb, lc]
	var start: int = -1
	var end: int = -1
	for edge in range(3):
		var other: int = (edge + 1) % 3
		if land[edge] == land[other]:
			continue
		var crossing: int = _crossing(ids[edge], ids[other])
		if land[edge]:
			start = crossing
		else:
			end = crossing
	# Directed triangles keep land on the left: outer land rings have positive
	# signed area; water holes have negative signed area in map coordinates.
	_next[start] = end
	_incoming[end] = start


func _crossing(a: int, b: int) -> int:
	var low: int = mini(a, b)
	var high: int = maxi(a, b)
	var key: int = low * display_heights.size() + high
	if _node_ids.has(key):
		return _node_ids[key]
	var h0: float = display_heights[low]
	var h1: float = display_heights[high]
	var weight: float = clampf((0.2 - h0) / (h1 - h0), 0.0, 1.0)
	var p0 := Vector2(low % contour_size.x, low / contour_size.x)
	var p1 := Vector2(high % contour_size.x, high / contour_size.x)
	var point: Vector2 = p0.lerp(p1, weight) / Vector2(contour_size - Vector2i.ONE) * map_size
	var id: int = _nodes.size()
	_node_ids[key] = id
	_nodes.append(point)
	return id


func _trace(start: int) -> void:
	var points := PackedVector2Array()
	var cursor: int = start
	var closed: bool = false
	while _visited[cursor] == 0:
		_visited[cursor] = 1
		if points.is_empty() or points[points.size() - 1] != _nodes[cursor]:
			points.append(_nodes[cursor])
		if not _next.has(cursor):
			break
		cursor = _next[cursor]
		if cursor == start:
			closed = true
			break
	if closed and points.size() > 1 and points[0] == points[points.size() - 1]:
		points.resize(points.size() - 1)
	if points.size() < (3 if closed else 2):
		discarded_contours += 1
		return
	var area: float = signed_area(points) if closed else 0.0
	var length: float = 0.0
	for i in range(points.size() if closed else points.size() - 1):
		length += points[i].distance_to(points[(i + 1) % points.size()])
	if length == 0.0 or (closed and area == 0.0):
		discarded_contours += 1
		return
	coastlines.append({"points": points, "closed": closed, "hole": closed and area < 0.0, "signed_area": area, "length": length})


static func signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	# Subtract an origin to avoid cancellation on small rings in large maps.
	var origin: Vector2 = points[0]
	for i in range(points.size()):
		area += (points[i] - origin).cross(points[(i + 1) % points.size()] - origin)
	return area * 0.5


func cell_info(cell: int) -> Dictionary:
	var feature: Dictionary = features[feature_ids[cell]]
	return {"feature_id": feature.id, "feature_kind": feature.kind,
		"feature_area": feature.area, "feature_cells": feature.cell_count,
		"touches_border": feature.touches_border, "coastal": coastal[cell] != 0,
		"coast_distance": distance_to_coast[cell], "depth": int(depth[cell])}


func snapshot() -> Dictionary:
	var paths: Array = []
	for coast in coastlines:
		var coordinates: Array = []
		for point in coast.points:
			coordinates.append([point.x, point.y])
		paths.append({"points": coordinates, "closed": coast.closed, "hole": coast.hole, "signed_area": coast.signed_area, "length": coast.length})
	return {"version": VERSION, "source_hash": source_hash, "sea_datum": SEA_DATUM,
		"feature_ids": Array(feature_ids), "coastal": Array(coastal), "distance_to_coast": Array(distance_to_coast), "depth": Array(depth),
		"features": features.duplicate(true), "contour_size": [contour_size.x, contour_size.y], "coastlines": paths, "discarded_contours": discarded_contours}


static func validate_cache(data: Variant, source: Dictionary, size: Vector2, smoothing: int) -> String:
	if not data is Dictionary:
		return "Missing geography data."
	if source.is_empty():
		return "" if data.is_empty() else "Legacy terrain cannot contain cell geography without a graph."
	if not _integer(data.get("version"), 1, VERSION) or not _integer(data.get("sea_datum"), SEA_DATUM, SEA_DATUM) or not data.get("source_hash") is String:
		return "Unsupported geography data."
	if data.source_hash != Graph.snapshot_fingerprint(source, size, smoothing):
		return "Geography does not match the saved graph and smoothing."
	var count: int = source.heights.size()
	for key in ["feature_ids", "coastal", "distance_to_coast", "depth"]:
		if not data.get(key) is Array or data[key].size() != count:
			return "Invalid geography cell array: " + key
	if not data.get("features") is Array or data.features.is_empty() or data.features.size() > count:
		return "Invalid geographic features."
	var counts := PackedInt32Array()
	counts.resize(data.features.size())
	for cell in range(count):
		if not _integer(data.feature_ids[cell], 0, counts.size() - 1) or not _integer(data.coastal[cell], 0, 1) or not _integer(data.depth[cell], 0, SEA_DATUM):
			return "Invalid cell feature, coast or depth data."
		if data.depth[cell] != maxi(0, SEA_DATUM - int(source.heights[cell])):
			return "Saved depth conflicts with the source heights."
		if not _number(data.distance_to_coast[cell], -1.0, size.length() * count) or (data.distance_to_coast[cell] < 0.0 and data.distance_to_coast[cell] != -1.0):
			return "Invalid coast distance."
		if data.coastal[cell] == 1 and data.distance_to_coast[cell] != 0.0:
			return "Coastal cells must have zero coast distance."
		counts[int(data.feature_ids[cell])] += 1
	var area: float = 0.0
	for id in range(data.features.size()):
		var feature: Variant = data.features[id]
		if not feature is Dictionary or not _integer(feature.get("id"), id, id) or not _integer(feature.get("first_cell"), 0, count - 1) or not _integer(feature.get("cell_count"), 1, count):
			return "Invalid geographic feature identity."
		if feature.cell_count != counts[id] or data.feature_ids[int(feature.first_cell)] != id or not feature.get("touches_border") is bool or not _number(feature.get("area"), 0.0, size.x * size.y * 1.01):
			return "Invalid geographic feature count, border or area."
		if feature.get("kind") not in (["landmass", "open_water", "inland_water"] if data.version == 1 else ["landmass", "island", "open_water", "inland_water"]):
			return "Unknown geographic feature kind."
		if (feature.kind == "open_water" and not feature.touches_border) or (feature.kind == "inland_water" and feature.touches_border):
			return "Water classification conflicts with its border."
		if data.version >= 2 and feature.kind in ["landmass", "island"] and feature.kind != land_kind(feature.area, feature.touches_border, size.x * size.y):
			return "Land size classification conflicts with its area or border."
		area += feature.area
	if absf(area / (size.x * size.y) - 1.0) > 0.01:
		return "Geographic feature areas do not cover the map."
	for cell in range(count):
		if (data.features[int(data.feature_ids[cell])].kind in ["landmass", "island"]) != (source.heights[cell] >= SEA_DATUM):
			return "Cell land classification conflicts with source heights."
	var expected_size: Vector2i = Grid.sample_size_for(size, clampi(maxi(int(source.columns), int(source.rows)) * 2, 32, 512))
	if not data.get("contour_size") is Array or data.contour_size.size() != 2 or not _integer(data.contour_size[0], 3, 513) or not _integer(data.contour_size[1], 3, 513) or not data.get("coastlines") is Array:
		return "Invalid shoreline layout."
	if Vector2i(int(data.contour_size[0]), int(data.contour_size[1])) != expected_size:
		return "Invalid shoreline layout."
	var limit: int = (expected_size.x - 1) * (expected_size.y - 1) * 4
	if data.coastlines.size() > limit or not _integer(data.get("discarded_contours"), 0, limit):
		return "Too many shoreline paths."
	var examined: int = 0
	for coast in data.coastlines:
		if not coast is Dictionary or not coast.get("points") is Array or not coast.get("closed") is bool or not coast.get("hole") is bool:
			return "Invalid shoreline path."
		examined += coast.points.size()
		if examined > limit or coast.points.size() < (3 if coast.closed else 2):
			return "Invalid shoreline vertex count."
		if not _number(coast.get("signed_area"), -size.x * size.y, size.x * size.y) or not _number(coast.get("length"), 0.0, size.length() * coast.points.size()):
			return "Invalid shoreline measurements."
		var points := PackedVector2Array()
		for point in coast.points:
			if not point is Array or point.size() != 2 or not _number(point[0], 0.0, size.x) or not _number(point[1], 0.0, size.y):
				return "Shoreline point lies outside the map."
			points.append(Vector2(point[0], point[1]))
		var signed: float = signed_area(points) if coast.closed else 0.0
		if absf(signed - coast.signed_area) > maxf(0.001, absf(signed) * 0.00001) or coast.hole != (coast.closed and signed < 0.0):
			return "Shoreline orientation or hole data is inconsistent."
	return ""


static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high


static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value, low, high) and float(value) == floorf(float(value))
