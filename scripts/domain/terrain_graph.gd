extends RefCounted
## Jittered cell sites and true Voronoi adjacency (the dual Delaunay edges).
## Source graph construction adapted under MIT; Godot owns triangulation.

const Alea = preload("res://scripts/domain/alea.gd")
var map_size := Vector2.ZERO
var requested_points: int = 10000
var spacing: float
var columns: int
var rows: int
var count: int
var points := PackedVector2Array() # Real sites followed by boundary pseudo-sites.
var triangles := PackedInt32Array()
var neighbors: Array = []
var _cell_triangles: Array = []
var _polygons: Dictionary = {}
var _areas := PackedFloat64Array()
var _boundary := PackedByteArray()
var heights := PackedByteArray(): # Source cell data: integers 0..100, sea datum 20.
	set(value):
		heights = value
		invalidate_display()
var uncovered_samples: int = 0
var _display_values := PackedFloat64Array()
var _display_gradients := PackedVector2Array()
var _display_smoothing: int = -1
var _triangle_starts := PackedInt32Array()


func generate(size: Vector2, desired: int, seed_text: String) -> void:
	map_size = size
	requested_points = desired
	spacing = maxf(0.01, _round2(sqrt(size.x * size.y / desired)))
	columns = floori((size.x + 0.5 * spacing - 1e-10) / spacing)
	rows = floori((size.y + 0.5 * spacing - 1e-10) / spacing)
	var random = Alea.new(seed_text)
	points.clear()
	for y in range(rows):
		for x in range(columns):
			points.append(Vector2(minf(_round2((x + 0.5) * spacing + (random.next() * 0.9 - 0.45) * spacing), size.x), minf(_round2((y + 0.5) * spacing + (random.next() * 0.9 - 0.45) * spacing), size.y)))
	count = points.size()
	var offset: float = floorf(-spacing + 0.5)
	var boundary_width: float = size.x - offset * 2.0
	var boundary_height: float = size.y - offset * 2.0
	var nx: int = ceili(boundary_width / (spacing * 2.0)) - 1
	var ny: int = ceili(boundary_height / (spacing * 2.0)) - 1
	for i in range(nx):
		var x: float = ceilf(boundary_width * (i + 0.5) / nx + offset)
		points.append(Vector2(x, offset))
		points.append(Vector2(x, boundary_height + offset))
	for i in range(ny):
		var y: float = ceilf(boundary_height * (i + 0.5) / ny + offset)
		points.append(Vector2(offset, y))
		points.append(Vector2(boundary_width + offset, y))
	triangles = Geometry2D.triangulate_delaunay(points)
	heights.resize(count)
	heights.fill(0)
	_build_topology()


func _build_topology() -> void:
	_polygons.clear()
	_areas.resize(count)
	_areas.fill(-1.0)
	_boundary.resize(count)
	_boundary.fill(0)
	invalidate_display()
	_triangle_starts.clear()
	for i in range(0, triangles.size(), 3):
		_triangle_starts.append(i)
	neighbors.clear()
	_cell_triangles.clear()
	for i in range(count):
		neighbors.append([])
		_cell_triangles.append([])
	for triangle in range(0, triangles.size(), 3):
		for edge in range(3):
			var a: int = triangles[triangle + edge]
			var b: int = triangles[triangle + (edge + 1) % 3]
			if a < count:
				_cell_triangles[a].append(triangle)
			if a >= count or b >= count:
				continue
			if b not in neighbors[a]:
				neighbors[a].append(b)
			if a not in neighbors[b]:
				neighbors[b].append(a)
	# Stable cyclic order; no fixed grid directions enter the terrain operations.
	for cell in range(count):
		var origin: Vector2 = points[cell]
		neighbors[cell].sort_custom(func(a: int, b: int): return (points[a] - origin).angle() < (points[b] - origin).angle())


func find_cell(x: float, y: float) -> int:
	return clampi(floori(y / spacing), 0, rows - 1) * columns + clampi(floori(x / spacing), 0, columns - 1)


func nearest_cell(point: Vector2) -> int:
	var column: int = clampi(floori(point.x / spacing), 0, columns - 1)
	var row: int = clampi(floori(point.y / spacing), 0, rows - 1)
	var nearest: int = find_cell(point.x, point.y)
	var distance: float = INF
	for y in range(maxi(0, row - 2), mini(rows, row + 3)):
		for x in range(maxi(0, column - 2), mini(columns, column + 3)):
			var cell: int = y * columns + x
			var candidate: float = point.distance_squared_to(points[cell])
			if candidate < distance:
				distance = candidate
				nearest = cell
	return nearest


func polygon(cell: int) -> PackedVector2Array:
	if _polygons.has(cell):
		return _polygons[cell]
	var centers: Array[Vector2] = []
	var origin: Vector2 = points[cell]
	for triangle in _cell_triangles[cell]:
		var a: Vector2 = points[triangles[triangle]]
		var b: Vector2 = points[triangles[triangle + 1]] - a
		var c: Vector2 = points[triangles[triangle + 2]] - a
		var denominator: float = 2.0 * b.cross(c)
		if absf(denominator) > 1e-12:
			centers.append(a + Vector2(c.y * b.length_squared() - b.y * c.length_squared(), b.x * c.length_squared() - c.x * b.length_squared()) / denominator)
	centers.sort_custom(func(a: Vector2, b: Vector2): return (a - origin).angle() < (b - origin).angle())
	var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(PackedVector2Array(centers), PackedVector2Array([Vector2.ZERO, Vector2(map_size.x, 0), map_size, Vector2(0, map_size.y)]))
	var result: PackedVector2Array = clipped[0] if not clipped.is_empty() else PackedVector2Array()
	_polygons[cell] = result
	return result


func cell_area(cell: int) -> float:
	if _areas[cell] < 0.0:
		var vertices: PackedVector2Array = polygon(cell)
		var twice_area: float = 0.0
		var origin: Vector2 = vertices[0] if not vertices.is_empty() else Vector2.ZERO
		for i in range(vertices.size()):
			twice_area += (vertices[i] - origin).cross(vertices[(i + 1) % vertices.size()] - origin)
		_areas[cell] = absf(twice_area) * 0.5
	return _areas[cell]


func touches_border(cell: int) -> bool:
	if _boundary[cell] == 0:
		_boundary[cell] = 1
		var vertices: PackedVector2Array = polygon(cell)
		var epsilon: float = maxf(map_size.x, map_size.y) * 0.000001
		for i in range(vertices.size()):
			var a: Vector2 = vertices[i]
			var b: Vector2 = vertices[(i + 1) % vertices.size()]
			if a.distance_squared_to(b) <= epsilon * epsilon:
				continue
			if (absf(a.x) <= epsilon and absf(b.x) <= epsilon) or (absf(a.y) <= epsilon and absf(b.y) <= epsilon) or (absf(a.x - map_size.x) <= epsilon and absf(b.x - map_size.x) <= epsilon) or (absf(a.y - map_size.y) <= epsilon and absf(b.y - map_size.y) <= epsilon):
				_boundary[cell] = 2
				break
	return _boundary[cell] == 2


func source_fingerprint(smoothing: int) -> String:
	return _fingerprint(points, triangles, heights, map_size, columns, rows, spacing, smoothing)


static func snapshot_fingerprint(data: Dictionary, size: Vector2, smoothing: int) -> String:
	var sites := PackedVector2Array()
	for point in data.points:
		sites.append(Vector2(point[0], point[1]))
	return _fingerprint(sites, PackedInt32Array(data.triangles), PackedByteArray(data.heights), size, int(data.columns), int(data.rows), float(data.spacing), smoothing)


static func _fingerprint(sites: PackedVector2Array, topology: PackedInt32Array, values: PackedByteArray, size: Vector2, width: int, height: int, step: float, smoothing: int) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("terrain-graph-v1".to_utf8_buffer())
	# Canonical geometric precision avoids false identity changes from JSON
	# decimal parsing while keeping source geometry and display choices bound.
	context.update(PackedFloat32Array([size.x, size.y, step]).to_byte_array())
	context.update(PackedInt32Array([width, height, smoothing]).to_byte_array())
	context.update(sites.to_byte_array())
	context.update(topology.to_byte_array())
	context.update(values)
	return context.finish().hex_encode()


func invalidate_display() -> void:
	_display_smoothing = -1


func _prepare_display(smoothing: int) -> void:
	if _display_smoothing == smoothing:
		return
	# Display filtering never changes authoritative integer cell heights.
	var values := PackedFloat64Array()
	values.resize(count)
	for cell in range(count):
		values[cell] = heights[cell]
	for pass_index in range(smoothing):
		var previous: PackedFloat64Array = values.duplicate()
		for cell in range(count):
			var sum: float = previous[cell]
			for neighbor in neighbors[cell]:
				sum += previous[neighbor]
			values[cell] = (previous[cell] + sum / (neighbors[cell].size() + 1)) * 0.5
	values.resize(points.size())
	for i in range(count, points.size()):
		values[i] = values[find_cell(points[i].x, points[i].y)]
	var gradients := PackedVector2Array()
	gradients.resize(points.size())
	if smoothing > 0:
		for cell in range(count):
			var xx: float = 0.0
			var xy: float = 0.0
			var yy: float = 0.0
			var xh: float = 0.0
			var yh: float = 0.0
			for neighbor in neighbors[cell]:
				var delta: Vector2 = points[neighbor] - points[cell]
				var change: float = (values[neighbor] - values[cell]) / 100.0
				xx += delta.x * delta.x
				xy += delta.x * delta.y
				yy += delta.y * delta.y
				xh += delta.x * change
				yh += delta.y * change
			var determinant: float = xx * yy - xy * xy
			if absf(determinant) > 1e-12:
				gradients[cell] = Vector2((yy * xh - xy * yh) / determinant, (xx * yh - xy * xh) / determinant)
		for i in range(count, points.size()):
			gradients[i] = gradients[find_cell(points[i].x, points[i].y)]
	_display_values = values
	_display_gradients = gradients
	_display_smoothing = smoothing


func rasterize(size: Vector2i, smoothing: int) -> PackedFloat32Array:
	_prepare_display(smoothing)
	var values: PackedFloat64Array = _display_values
	var gradients: PackedVector2Array = _display_gradients
	var output := PackedFloat32Array()
	output.resize(size.x * size.y)
	output.fill(-1.0)
	var scale: Vector2 = Vector2(size - Vector2i.ONE) / map_size
	for t in _triangle_starts:
		var a: Vector2 = (points[triangles[t]]) * scale
		var b: Vector2 = (points[triangles[t + 1]]) * scale
		var c: Vector2 = (points[triangles[t + 2]]) * scale
		var ab: Vector2 = b - a
		var ac: Vector2 = c - a
		var denominator: float = ab.cross(ac)
		if absf(denominator) < 1e-12:
			continue
		var low: Vector2i = Vector2i(ceili(minf(a.x, minf(b.x, c.x))), ceili(minf(a.y, minf(b.y, c.y)))).max(Vector2i.ZERO)
		var high: Vector2i = Vector2i(floori(maxf(a.x, maxf(b.x, c.x))), floori(maxf(a.y, maxf(b.y, c.y)))).min(size - Vector2i.ONE)
		var ha: float = values[triangles[t]] / 100.0
		var hb: float = values[triangles[t + 1]] / 100.0
		var hc: float = values[triangles[t + 2]] / 100.0
		# A bounded cubic Bezier patch. Shared edges use the same endpoint heights
		# and gradients, so adjacent patches meet without cracks or axial blur.
		var ga: Vector2 = gradients[triangles[t]]
		var gb: Vector2 = gradients[triangles[t + 1]]
		var gc: Vector2 = gradients[triangles[t + 2]]
		var world_ab: Vector2 = points[triangles[t + 1]] - points[triangles[t]]
		var world_ac: Vector2 = points[triangles[t + 2]] - points[triangles[t]]
		var world_bc: Vector2 = points[triangles[t + 2]] - points[triangles[t + 1]]
		var aab: float = clampf(ha + ga.dot(world_ab) / 3.0, minf(ha, hb), maxf(ha, hb))
		var aac: float = clampf(ha + ga.dot(world_ac) / 3.0, minf(ha, hc), maxf(ha, hc))
		var abb: float = clampf(hb - gb.dot(world_ab) / 3.0, minf(ha, hb), maxf(ha, hb))
		var bbc: float = clampf(hb + gb.dot(world_bc) / 3.0, minf(hb, hc), maxf(hb, hc))
		var acc: float = clampf(hc - gc.dot(world_ac) / 3.0, minf(ha, hc), maxf(ha, hc))
		var bcc: float = clampf(hc - gc.dot(world_bc) / 3.0, minf(hb, hc), maxf(hb, hc))
		var center: float = clampf((aab + aac + abb + bbc + acc + bcc) * 0.25 - (ha + hb + hc) / 6.0, minf(ha, minf(hb, hc)), maxf(ha, maxf(hb, hc)))
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var dx: float = x - a.x
				var dy: float = y - a.y
				var u: float = (dx * ac.y - dy * ac.x) / denominator
				var v: float = (ab.x * dy - ab.y * dx) / denominator
				if u >= -0.00001 and v >= -0.00001 and u + v <= 1.00001:
					var height: float = ha + (hb - ha) * u + (hc - ha) * v
					if smoothing > 0:
						var w: float = 1.0 - u - v
						height = w * w * w * ha + u * u * u * hb + v * v * v * hc + 3.0 * (w * w * u * aab + w * w * v * aac + w * u * u * abb + u * u * v * bbc + w * v * v * acc + u * v * v * bcc) + 6.0 * w * u * v * center
					output[y * size.x + x] = clampf(height, 0.0, 1.0)
	# Extend the nearest site's value outside the triangulated boundary hull.
	# Also accounts for float32 edge roundoff; coverage is visible to tests.
	uncovered_samples = 0
	for i in range(output.size()):
		if output[i] < 0.0:
			uncovered_samples += 1
			var point := Vector2(i % size.x, i / size.x) / scale
			output[i] = values[nearest_cell(point)] / 100.0
	return output


func snapshot() -> Dictionary:
	var coordinates: Array = []
	for point in points:
		coordinates.append([point.x, point.y])
	return {"points": coordinates, "triangles": Array(triangles), "heights": Array(heights), "columns": columns, "rows": rows, "spacing": spacing}


func restore(data: Dictionary, size: Vector2, desired: int) -> void:
	map_size = size
	requested_points = desired
	columns = int(data.columns)
	rows = int(data.rows)
	spacing = float(data.spacing)
	points.clear()
	for point in data.points:
		points.append(Vector2(point[0], point[1]))
	heights = PackedByteArray(data.heights)
	count = heights.size()
	triangles = PackedInt32Array(data.triangles)
	_build_topology()


static func _round2(value: float) -> float:
	return floorf(value * 100.0 + 0.5) / 100.0
