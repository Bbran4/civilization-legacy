extends RefCounted
## Independent connected land regions over the final terrain; no scenario ownership.
const Payload = preload("res://scripts/storage/float_payload.gd")
var source_hash := ""
var size := Vector2i.ZERO
var ids := PackedInt32Array()
var records: Array[Dictionary] = []
var requested_count := 64
var ocean_generated := false
var requested_oceans := 24
var ocean_style := "coastal_band"
var coastal_reach := 64.0
var sea_mask := PackedByteArray()
var _image: Image
var _land_components := PackedInt32Array()
var _heap: Array[Vector2i] = []
var _texture: ImageTexture

func generate(base: PackedFloat32Array, surface: RefCounted, water: RefCounted, count: int = 64) -> String:
	if surface == null or water == null:
		return "Build the terrain surface and water layer first."
	if count < 1 or count > 512 or base.size() != surface.heights.size() or water.mask_size != surface.size or surface.size.x < 3 or surface.size.y < 3 or maxi(surface.size.x, surface.size.y) > 2050 or base.size() != surface.size.x * surface.size.y or water.mask_bytes.size() != base.size() * 4:
		return "Invalid province inputs or count (1-512)."
	source_hash = surface.fingerprint()
	size = surface.size
	requested_count = count
	ids.resize(base.size())
	ids.fill(0)
	ocean_generated = false
	sea_mask.clear()
	records.clear()
	_texture = null
	_image = null
	_heap.clear()
	var land := PackedByteArray()
	land.resize(base.size())
	var candidates := PackedInt32Array()
	for i in range(base.size()):
		if base[i] >= 0.2 and water.mask_bytes[i * 4 + 1] == 0:
			land[i] = 1
			candidates.append(i)
	var distance := PackedInt32Array()
	distance.resize(base.size())
	distance.fill(2147483647)
	var rng := RandomNumberGenerator.new()
	rng.seed = source_hash.hash()
	var seeds := PackedInt32Array()
	# Best of 16 candidates spreads seeds without imposing a square grid.
	for _j in range(mini(count, candidates.size())):
		var best := -1
		var best_score := -1.0
		for _k in range(16):
			var pixel := candidates[rng.randi_range(0, candidates.size() - 1)]
			if ids[pixel] != 0:
				continue
			var point := Vector2(pixel % size.x, pixel / size.x)
			var score := INF
			for seed in seeds:
				score = minf(score, point.distance_squared_to(Vector2(seed % size.x, seed / size.x)))
			if score > best_score:
				best = pixel
				best_score = score
		if best >= 0:
			seeds.append(best)
			_seed(best, distance)
	_grow(land, distance, surface.heights, water.mask_bytes)
	# Every disconnected island receives an identity, even without a sampled seed.
	for pixel in candidates:
		if ids[pixel] == 0:
			if records.size() >= 65535:
				return "Too many disconnected land regions."
			_seed(pixel, distance)
			_grow(land, distance, surface.heights, water.mask_bytes)
	return _index_regions()

func _seed(pixel: int, distance: PackedInt32Array) -> void:
	var id := records.size() + 1
	records.append({"id": id, "name": "Province " + str(id), "pixels": 0, "neighbors": [], "kind": "land"})
	ids[pixel] = id
	distance[pixel] = 0
	_push(Vector2i(0, pixel))

func _neighbors(i: int) -> Array[int]:
	var result: Array[int] = []
	if i % size.x > 0: result.append(i - 1)
	if i % size.x < size.x - 1: result.append(i + 1)
	if i >= size.x: result.append(i - size.x)
	if i + size.x < ids.size(): result.append(i + size.x)
	return result

func _grow(land: PackedByteArray, distance: PackedInt32Array, heights: PackedFloat32Array, water: PackedByteArray) -> void:
	while not _heap.is_empty():
		var item := _pop()
		var i := item.y
		if item.x != distance[i]:
			continue
		for next in _neighbors(i):
			if land[next] == 0:
				continue
			var cost := 10 + mini(1000, roundi(absf(heights[next] - heights[i]) * 4096.0 * maxi(size.x, size.y) / 1025.0))
			if water[i * 4] > 64 or water[next * 4] > 64:
				cost += 30
			var d := item.x + cost
			if d < distance[next]:
				distance[next] = d
				ids[next] = ids[i]
				_push(Vector2i(d, next))

static func _less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
func _push(value: Vector2i) -> void:
	var i := _heap.size()
	_heap.append(value)
	while i > 0:
		var parent := (i - 1) / 2
		if not _less(value, _heap[parent]): break
		_heap[i] = _heap[parent]
		i = parent
	_heap[i] = value
func _pop() -> Vector2i:
	var result := _heap[0]
	var last: Vector2i = _heap.pop_back()
	if _heap.is_empty(): return result
	var i := 0
	while i * 2 + 1 < _heap.size():
		var child := i * 2 + 1
		if child + 1 < _heap.size() and _less(_heap[child + 1], _heap[child]): child += 1
		if not _less(_heap[child], last): break
		_heap[i] = _heap[child]
		i = child
	_heap[i] = last
	return result

func _index_regions(allow_absorption: bool = false) -> String:
	var counts := PackedInt32Array()
	counts.resize(records.size())
	var edges: Dictionary = {}
	var visited := PackedByteArray()
	visited.resize(ids.size())
	var regions: Dictionary = {}
	var land_components := PackedInt32Array()
	land_components.resize(ids.size())
	var component := 0
	# Separate islands may share an identity; pieces on the same island must connect.
	for i in range(ids.size()):
		if ids[i] < 0 or ids[i] > records.size(): return "Unknown province ID."
		if ids[i] == 0 or records[ids[i] - 1].get("kind", "land") != "land" or land_components[i] != 0: continue
		component += 1
		var queue := PackedInt32Array([i])
		land_components[i] = component
		var cursor := 0
		while cursor < queue.size():
			var pixel := queue[cursor]
			cursor += 1
			for next in _neighbors(pixel):
				if ids[next] > 0 and ids[next] <= records.size() and records[ids[next] - 1].get("kind", "land") == "land" and land_components[next] == 0:
					land_components[next] = component
					queue.append(next)
	_land_components = land_components
	var mass_lists: Array = []
	for _record in records: mass_lists.append([])
	var part_counts := PackedInt32Array()
	part_counts.resize(records.size())
	for i in range(ids.size()):
		var id := ids[i]
		if id < 0 or id > records.size(): return "Unknown province ID."
		if id == 0: continue
		counts[id - 1] += 1
		for next in [i + 1 if i % size.x < size.x - 1 else -1, i + size.x]:
			if next >= 0 and next < ids.size() and ids[next] > 0 and ids[next] != id:
				edges[Vector2i(mini(id, ids[next]), maxi(id, ids[next]))] = true
		if visited[i] == 0:
			var key := Vector2i(id, land_components[i])
			if regions.has(key): return "A region contains disconnected pieces on the same landmass or ocean."
			regions[key] = true
			part_counts[id - 1] += 1
			if land_components[i] > 0: mass_lists[id - 1].append(land_components[i])
			var queue := PackedInt32Array([i])
			visited[i] = 1
			var cursor := 0
			while cursor < queue.size():
				var pixel := queue[cursor]
				cursor += 1
				for next in _neighbors(pixel):
					if visited[next] == 0 and ids[next] == id:
						visited[next] = 1
						queue.append(next)
	for i in range(records.size()):
		if counts[i] == 0 and records[i].get("active", true):
			if allow_absorption and records[i].get("kind", "land") == "land": records[i].active = false
			else: return "A region has no pixels."
		if counts[i] > 0 and not records[i].get("active", true): return "An absorbed province still owns pixels."
		records[i].active = records[i].get("active", true)
		records[i].parts = part_counts[i]
		records[i].landmasses = mass_lists[i]
		records[i].pixels = counts[i]
		records[i].neighbors = []
	for edge in edges:
		records[edge.x - 1].neighbors.append(edge.y)
		records[edge.y - 1].neighbors.append(edge.x)
	for record in records: record.neighbors.sort()
	return ""

func id_at(uv: Vector2) -> int:
	var p := Vector2i((uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(size - Vector2i.ONE)).round())
	return ids[p.y * size.x + p.x]
func texture() -> ImageTexture:
	if _texture == null:
		var bytes := PackedByteArray()
		bytes.resize(ids.size() * 4)
		for i in range(ids.size()):
			bytes[i * 4] = ids[i] & 255
			bytes[i * 4 + 1] = (ids[i] >> 8) & 255
			bytes[i * 4 + 2] = 2 if ids[i] == 0 and sea_mask.size() == ids.size() and sea_mask[i] != 0 else (1 if ids[i] > 0 and records[ids[i] - 1].get("kind", "land") == "ocean" else 0)
			bytes[i * 4 + 3] = 255
		_image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
		_texture = ImageTexture.create_from_image(_image)
	return _texture
func snapshot() -> Dictionary:
	var values := PackedFloat32Array()
	values.resize(ids.size())
	for i in range(ids.size()): values[i] = ids[i]
	var sea_values := PackedFloat32Array()
	sea_values.resize(sea_mask.size())
	for i in range(sea_mask.size()): sea_values[i] = sea_mask[i]
	return {"version": 5, "coastal_reach": coastal_reach, "sea_mask": Payload.encode(sea_values) if not sea_values.is_empty() else null, "ocean_style": ocean_style, "ocean_generated": ocean_generated, "requested_oceans": requested_oceans, "source_hash": source_hash, "size": [size.x, size.y], "requested_count": requested_count, "ids": Payload.encode(values), "records": records.duplicate(true)}
static func decode(data: Variant) -> Dictionary:
	if data == null: return {"error": "", "layer": null}
	if not data is Dictionary or data.get("version") not in [1, 1.0, 2, 2.0, 3, 3.0, 4, 4.0, 5, 5.0] or not data.get("source_hash") is String or data.source_hash.length() != 64 or not data.get("size") is Array or data.size.size() != 2 or not data.get("records") is Array or data.records.size() > 65535:
		return {"error": "Invalid province document."}
	for v in data.size:
		if not (v is int or v is float) or not is_finite(float(v)) or v != int(v) or v < 3 or v > 2050: return {"error": "Invalid province dimensions."}
	var count: Variant = data.get("requested_count")
	if not (count is int or count is float) or not is_finite(float(count)) or count != int(count) or count < 1 or count > 512: return {"error": "Invalid province count."}
	var payload := Payload.decode(data.get("ids"), int(data.size[0]) * int(data.size[1]), 0, data.records.size())
	if not payload.error.is_empty(): return {"error": payload.error}
	var layer: RefCounted = load("res://scripts/domain/world_provinces.gd").new()
	layer.size = Vector2i(data.size[0], data.size[1])
	layer.source_hash = data.source_hash
	layer.requested_count = int(count)
	if int(data.version) >= 2:
		if not data.get("ocean_generated") is bool or not (data.get("requested_oceans") is int or data.get("requested_oceans") is float) or not is_finite(float(data.requested_oceans)) or data.requested_oceans != int(data.requested_oceans) or data.requested_oceans < 1 or data.requested_oceans > 256:
			return {"error": "Invalid ocean region settings."}
		layer.ocean_generated = data.ocean_generated
		layer.requested_oceans = int(data.requested_oceans)
	if int(data.version) >= 3:
		if data.get("ocean_style") not in ["open", "coastal", "coastal_band"]: return {"error": "Invalid sea partition style."}
		layer.ocean_style = data.ocean_style
	else: layer.ocean_style = "open"
	if layer.ocean_style == "coastal_band":
		var reach: Variant = data.get("coastal_reach")
		if int(data.version) < 4 or not (reach is int or reach is float) or not is_finite(float(reach)) or reach < 8 or reach > 256: return {"error": "Invalid coastal sea reach."}
		layer.coastal_reach = float(reach)
		if layer.ocean_generated:
			var sea := Payload.decode(data.get("sea_mask"), payload.values.size(), 0, 1)
			if not sea.error.is_empty(): return {"error": sea.error}
			layer.sea_mask.resize(sea.values.size())
			for i in range(sea.values.size()):
				if sea.values[i] != int(sea.values[i]): return {"error": "Invalid open ocean mask."}
				layer.sea_mask[i] = int(sea.values[i])
	layer.ids.resize(payload.values.size())
	for i in range(layer.ids.size()):
		layer.ids[i] = int(payload.values[i])
		if payload.values[i] != layer.ids[i]: return {"error": "Province IDs must be whole numbers."}
	var ocean_seen := false
	for i in range(data.records.size()):
		var record: Variant = data.records[i]
		if not record is Dictionary or record.get("id") != i + 1 or not record.get("name") is String or record.name.length() > 128: return {"error": "Invalid province identity."}
		if int(data.version) >= 2 and not record.get("kind", "land") is String: return {"error": "Invalid region kind."}
		var kind: String = record.get("kind", "land") if int(data.version) >= 2 else "land"
		if kind not in ["land", "ocean"] or (kind == "land" and ocean_seen and int(data.version) < 5) or (kind == "ocean" and not layer.ocean_generated): return {"error": "Invalid land/ocean region order."}
		ocean_seen = ocean_seen or kind == "ocean"
		if int(data.version) >= 3 and not record.get("active") is bool: return {"error": "Invalid absorbed province state."}
		layer.records.append({"id": i + 1, "name": record.name, "pixels": 0, "neighbors": [], "kind": kind, "active": record.get("active", true) if int(data.version) >= 3 else true})
	var error: String = layer._index_regions()
	return {"error": error, "layer": layer}

func validate_coverage(samples: PackedFloat32Array, land_datum: float, water: RefCounted) -> String:
	if samples.size() != ids.size() or water.mask_size != size:
		return "Province coverage dimensions do not match terrain."
	var classes := classify(samples, land_datum, water.mask_bytes, size)
	var band := coastal_band(classes, size, coastal_reach) if ocean_generated and ocean_style == "coastal_band" else PackedByteArray()
	for i in range(ids.size()):
		var expected: int = classes[i]
		if ocean_generated and ocean_style == "coastal_band":
			if sea_mask.size() != ids.size() or (sea_mask[i] != 0) != (classes[i] == 2): return "Open ocean mask does not match sea coverage."
			if expected == 2 and band[i] == 0: expected = 0
		if expected == 2 and not ocean_generated: expected = 0
		var actual := 0 if ids[i] == 0 else (2 if records[ids[i] - 1].kind == "ocean" else 1)
		if actual != expected: return "Region coverage must keep land, ocean and lakes separate."
	return ""

static func classify(samples: PackedFloat32Array, datum: float, mask: PackedByteArray, dimensions: Vector2i) -> PackedByteArray:
	var classes := PackedByteArray()
	classes.resize(samples.size())
	var queue := PackedInt32Array()
	for i in range(samples.size()):
		if mask[i * 4 + 1] > 0: continue
		if samples[i] >= datum:
			classes[i] = 1
		elif i < dimensions.x or i >= samples.size() - dimensions.x or i % dimensions.x == 0 or i % dimensions.x == dimensions.x - 1:
			classes[i] = 2
			queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var i := queue[cursor]
		cursor += 1
		for next in [i - 1 if i % dimensions.x > 0 else -1, i + 1 if i % dimensions.x < dimensions.x - 1 else -1, i - dimensions.x, i + dimensions.x]:
			if next >= 0 and next < samples.size() and classes[next] == 0 and samples[next] < datum and mask[next * 4 + 1] == 0:
				classes[next] = 2
				queue.append(next)
	return classes

func editable_copy() -> RefCounted:
	var copy: RefCounted = load("res://scripts/domain/world_provinces.gd").new()
	copy.source_hash = source_hash
	copy.size = size
	copy.ids = ids.duplicate()
	copy._land_components = _land_components
	copy.records.assign(records.duplicate(true))
	copy.requested_count = requested_count
	copy.ocean_generated = ocean_generated
	copy.requested_oceans = requested_oceans
	copy.ocean_style = ocean_style
	copy.coastal_reach = coastal_reach
	copy.sea_mask = sea_mask.duplicate()
	return copy

func generate_oceans(base: PackedFloat32Array, water: RefCounted, count: int = 24, style: String = "coastal_band", reach: float = 64.0) -> String:
	if not is_finite(reach) or reach < 8 or reach > 256 or style not in ["open", "coastal", "coastal_band"] or count < 1 or count > 256 or base.size() != ids.size() or water.mask_size != size: return "Invalid ocean region inputs."
	var classes := classify(base, 0.2, water.mask_bytes, size)
	var band := coastal_band(classes, size, reach) if style == "coastal_band" else PackedByteArray()
	sea_mask.clear()
	if style == "coastal_band":
		sea_mask.resize(ids.size())
		for i in range(ids.size()): sea_mask[i] = 1 if classes[i] == 2 else 0
	for record in records:
		if record.kind == "ocean": record.active = false
	for i in range(ids.size()):
		if ids[i] > 0 and records[ids[i] - 1].kind == "ocean": ids[i] = 0
	var allowed := PackedByteArray()
	allowed.resize(ids.size())
	var candidates := PackedInt32Array()
	for i in range(ids.size()):
		if classes[i] == 2 and (band.is_empty() or band[i] != 0):
			allowed[i] = 1
			candidates.append(i)
	var seed_candidates := PackedInt32Array()
	if style in ["coastal", "coastal_band"]:
		for i in candidates:
			for next in _neighbors(i):
				if classes[next] == 1:
					seed_candidates.append(i)
					break
	if seed_candidates.is_empty(): seed_candidates = candidates
	var distances := PackedInt32Array()
	distances.resize(ids.size())
	distances.fill(2147483647)
	_heap.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = (source_hash + "/oceans").hash()
	var seeds := PackedInt32Array()
	for _j in range(mini(count, mini(seed_candidates.size(), 65535 - records.size()))):
		var best := -1
		var best_score := -1.0
		for _k in range(16):
			var pixel := seed_candidates[rng.randi_range(0, seed_candidates.size() - 1)]
			if ids[pixel] != 0: continue
			var score := INF
			for seed in seeds: score = minf(score, Vector2(pixel % size.x, pixel / size.x).distance_squared_to(Vector2(seed % size.x, seed / size.x)))
			if score > best_score:
				best = pixel
				best_score = score
		if best >= 0:
			seeds.append(best)
			_ocean_seed(best, distances)
	var flat := PackedFloat32Array()
	flat.resize(ids.size())
	var no_rivers := PackedByteArray()
	no_rivers.resize(ids.size() * 4)
	_grow(allowed, distances, flat, no_rivers)
	for i in candidates:
		if ids[i] == 0:
			if records.size() >= 65535: return "Too many ocean regions."
			_ocean_seed(i, distances)
			_grow(allowed, distances, flat, no_rivers)
	coastal_reach = reach
	ocean_style = style
	ocean_generated = true
	requested_oceans = count
	_texture = null
	_image = null
	return _index_regions()

func _ocean_seed(pixel: int, distances: PackedInt32Array) -> void:
	_seed(pixel, distances)
	records[-1].kind = "ocean"
	records[-1].name = "Ocean " + str(records[-1].id)

func paint_segment(a: Vector2, b: Vector2, radius: float, target: int, changes: Dictionary, attach_islands: bool = false) -> void:
	if target < 1 or target > records.size() or not a.is_finite() or not b.is_finite() or not is_finite(radius) or radius <= 0: return
	var low := Vector2i((a.min(b) - Vector2.ONE * radius).floor()).max(Vector2i.ZERO)
	var high := Vector2i((a.max(b) + Vector2.ONE * radius).ceil()).min(size - Vector2i.ONE)
	var delta := b - a
	var islands: Dictionary = {}
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var p := Vector2(x, y)
			var t := clampf((p - a).dot(delta) / delta.length_squared(), 0, 1) if delta.length_squared() > 0 else 0.0
			if p.distance_to(a + delta * t) > radius: continue
			var i := y * size.x + x
			var previous := ids[i]
			if previous == 0 or previous == target or records[previous - 1].kind != records[target - 1].kind: continue
			if attach_islands and records[target - 1].kind == "land" and _land_components.size() == ids.size() and _land_components[i] not in records[target - 1].get("landmasses", []):
				islands[_land_components[i]] = true
			if not changes.has(i): changes[i] = previous
			ids[i] = target
			if _image != null: _image.set_pixel(x, y, _id_color(target))
	if not islands.is_empty():
		for i in range(ids.size()):
			if islands.has(_land_components[i]) and ids[i] != target:
				if not changes.has(i): changes[i] = ids[i]
				ids[i] = target
				if _image != null: _image.set_pixel(i % size.x, i / size.x, _id_color(target))
	if _texture != null: _texture.update(_image)

func _id_color(id: int) -> Color:
	return Color8(id & 255, (id >> 8) & 255, 1 if records[id - 1].kind == "ocean" else 0, 255)

static func coastal_band(classes: PackedByteArray, dimensions: Vector2i, reach: float) -> PackedByteArray:
	var limit := maxf(1.0, reach * maxi(dimensions.x, dimensions.y) / 1025.0)
	var distance := PackedFloat32Array()
	distance.resize(classes.size())
	distance.fill(limit + 2.0)
	for i in range(classes.size()):
		if classes[i] != 2: continue
		for next in [i - 1 if i % dimensions.x > 0 else -1, i + 1 if i % dimensions.x < dimensions.x - 1 else -1, i - dimensions.x, i + dimensions.x]:
			if next >= 0 and next < classes.size() and classes[next] == 1:
				distance[i] = 0
				break
	# Chamfer sweeps keep the outer sea envelope broad and coast-following.
	for forward in [true, false]:
		var step := 1 if forward else -1
		for i in range(0 if forward else classes.size() - 1, classes.size() if forward else -1, step):
			if classes[i] != 2: continue
			var x := i % dimensions.x
			var y := i / dimensions.x
			if (x > 0 if forward else x < dimensions.x - 1) and classes[i - step] == 2:
				distance[i] = minf(distance[i], distance[i - step] + 1.0)
			if y > 0 if forward else y < dimensions.y - 1:
				var row := i - step * dimensions.x
				if classes[row] == 2: distance[i] = minf(distance[i], distance[row] + 1.0)
				for dx in [-1, 1]:
					if x + dx >= 0 and x + dx < dimensions.x and classes[row + dx] == 2:
						distance[i] = minf(distance[i], distance[row + dx] + 1.41421356)
	var result := PackedByteArray()
	result.resize(classes.size())
	for i in range(classes.size()): result[i] = 1 if classes[i] == 2 and distance[i] <= limit else 0
	return result

func split_region(id: int, points: PackedVector2Array) -> Dictionary:
	if id < 1 or id > records.size() or not records[id - 1].active or points.size() < 2: return {"error": "Select a province and draw a complete split line."}
	if records.size() >= 65535: return {"error": "No unused province IDs remain."}
	var barrier: Dictionary = {}
	for j in range(points.size() - 1):
		if not points[j].is_finite() or not points[j + 1].is_finite(): return {"error": "Invalid split line."}
		var a := Vector2i(points[j].round()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
		var b := Vector2i(points[j + 1].round()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
		var dx := absi(b.x - a.x)
		var dy := -absi(b.y - a.y)
		var sx := 1 if a.x < b.x else -1
		var sy := 1 if a.y < b.y else -1
		var error := dx + dy
		while true:
			var pixel := a.y * size.x + a.x
			if ids[pixel] == id: barrier[pixel] = true
			if a == b: break
			var twice := 2 * error
			if twice >= dy:
				error += dy
				a.x += sx
			if twice <= dx:
				error += dx
				a.y += sy
	if barrier.is_empty(): return {"error": "Draw the line through the selected province."}
	var part := PackedByteArray()
	part.resize(ids.size())
	var queue := PackedInt32Array([int(barrier.keys()[0])])
	part[queue[0]] = 1
	var cursor := 0
	while cursor < queue.size():
		var pixel := queue[cursor]
		cursor += 1
		for next in _neighbors(pixel):
			if part[next] == 0 and ids[next] == id:
				part[next] = 1
				queue.append(next)
	for pixel in barrier:
		if part[pixel] == 0: return {"error": "Split one island part at a time."}
	var labels := PackedByteArray()
	labels.resize(ids.size())
	var groups: Array[PackedInt32Array] = []
	for pixel in queue:
		if labels[pixel] != 0 or barrier.has(pixel): continue
		if groups.size() == 2: return {"error": "This line creates more than two pieces. Draw a simpler split."}
		var group := PackedInt32Array([pixel])
		var label := groups.size() + 1
		labels[pixel] = label
		cursor = 0
		while cursor < group.size():
			var cell := group[cursor]
			cursor += 1
			for next in _neighbors(cell):
				if part[next] != 0 and labels[next] == 0 and not barrier.has(next):
					labels[next] = label
					group.append(next)
		groups.append(group)
	if groups.size() != 2: return {"error": "Extend the line across the province, or close it into a loop."}
	# Assign cut pixels from their adjacent side so no land/water holes are created.
	var frontier := PackedInt32Array()
	for pixel in barrier:
		for next in _neighbors(pixel):
			if labels[next] > 0:
				labels[pixel] = labels[next]
				frontier.append(pixel)
				break
	cursor = 0
	while cursor < frontier.size():
		var pixel := frontier[cursor]
		cursor += 1
		for next in _neighbors(pixel):
			if barrier.has(next) and labels[next] == 0:
				labels[next] = labels[pixel]
				frontier.append(next)
	var new_label := 1 if groups[0].size() <= groups[1].size() else 2
	var new_id := records.size() + 1
	var changes: Dictionary = {}
	for pixel in queue:
		if labels[pixel] == new_label:
			changes[pixel] = id
			ids[pixel] = new_id
	records.append({"id": new_id, "name": records[id - 1].name.left(108) + " split " + str(new_id), "kind": records[id - 1].kind, "active": true})
	_texture = null
	_image = null
	return {"error": "", "changes": changes, "new_id": new_id}
