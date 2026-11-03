extends RefCounted
## Independent connected land regions over the final terrain; no scenario ownership.
const Payload = preload("res://scripts/storage/float_payload.gd")
var source_hash := ""
var size := Vector2i.ZERO
var ids := PackedInt32Array()
var records: Array[Dictionary] = []
var requested_count := 64
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
	records.clear()
	_texture = null
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
	records.append({"id": id, "name": "Province " + str(id), "pixels": 0, "neighbors": []})
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

func _index_regions() -> String:
	var counts := PackedInt32Array()
	counts.resize(records.size())
	var edges: Dictionary = {}
	var visited := PackedByteArray()
	visited.resize(ids.size())
	var regions: Dictionary = {}
	for i in range(ids.size()):
		var id := ids[i]
		if id < 0 or id > records.size(): return "Unknown province ID."
		if id == 0: continue
		counts[id - 1] += 1
		for next in [i + 1 if i % size.x < size.x - 1 else -1, i + size.x]:
			if next >= 0 and next < ids.size() and ids[next] > 0 and ids[next] != id:
				edges[Vector2i(mini(id, ids[next]), maxi(id, ids[next]))] = true
		if visited[i] == 0:
			if regions.has(id): return "A province contains disconnected regions."
			regions[id] = true
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
		if counts[i] == 0: return "A province has no land."
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
			bytes[i * 4 + 3] = 255
		_texture = ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes))
	return _texture
func snapshot() -> Dictionary:
	var values := PackedFloat32Array()
	values.resize(ids.size())
	for i in range(ids.size()): values[i] = ids[i]
	return {"version": 1, "source_hash": source_hash, "size": [size.x, size.y], "requested_count": requested_count, "ids": Payload.encode(values), "records": records.duplicate(true)}
static func decode(data: Variant) -> Dictionary:
	if data == null: return {"error": "", "layer": null}
	if not data is Dictionary or data.get("version") != 1 or not data.get("source_hash") is String or data.source_hash.length() != 64 or not data.get("size") is Array or data.size.size() != 2 or not data.get("records") is Array or data.records.size() > 65535:
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
	layer.ids.resize(payload.values.size())
	for i in range(layer.ids.size()):
		layer.ids[i] = int(payload.values[i])
		if payload.values[i] != layer.ids[i]: return {"error": "Province IDs must be whole numbers."}
	for i in range(data.records.size()):
		var record: Variant = data.records[i]
		if not record is Dictionary or record.get("id") != i + 1 or not record.get("name") is String or record.name.length() > 128: return {"error": "Invalid province identity."}
		layer.records.append({"id": i + 1, "name": record.name, "pixels": 0, "neighbors": []})
	var error: String = layer._index_regions()
	return {"error": error, "layer": layer}

func validate_coverage(samples: PackedFloat32Array, land_datum: float, water: RefCounted) -> String:
	if samples.size() != ids.size() or water.mask_size != size:
		return "Province coverage dimensions do not match terrain."
	for i in range(ids.size()):
		var land: bool = samples[i] >= land_datum and water.mask_bytes[i * 4 + 1] == 0
		if (ids[i] > 0) != land:
			return "Province coverage must assign all land and exclude sea and lakes."
	return ""
