extends RefCounted
## Independent connected land regions over the final terrain; no scenario ownership.
const Payload = preload("res://scripts/storage/float_payload.gd")
const Seas = preload("res://scripts/domain/sea_coverage.gd")
var enclosed_seas := true
var source_hash := ""
var size := Vector2i.ZERO
var ids := PackedInt32Array()
var records: Array[Dictionary] = []
var nations: Array[Dictionary] = []
## Derived movement hooks. Each record links two province IDs and a crossing type.
var connections: Array[Dictionary] = []
var border_revision := 0
var border_geometry: RefCounted
var requested_count := 64
var ocean_generated := false
var inland_generated := false
var land_includes_sea_datum := false
var requested_oceans := 24
var ocean_style := "coastal_band"
var coastal_reach := 64.0
var sea_mask := PackedByteArray()
var impassable := PackedByteArray()
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
	inland_generated = false
	land_includes_sea_datum = false
	enclosed_seas = true
	sea_mask.clear()
	impassable.clear()
	records.clear()
	_texture = null
	_image = null
	_heap.clear()
	var land := PackedByteArray()
	land.resize(base.size())
	var candidates := PackedInt32Array()
	var classes := classify(base,0.2,water.mask_bytes,size)
	for i in range(base.size()):
		if classes[i] == 1:
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
	# Province fronts should respond to broad terrain shape, not single-pixel
	# height noise. Keep the original heightmap untouched; only the slope cost
	# field is lightly smoothed for deterministic, less ragged boundaries.
	var growth_heights := _growth_heights(surface.heights)
	_grow(land, distance, growth_heights, water.mask_bytes)
	# Every disconnected island receives an identity, even without a sampled seed.
	for pixel in candidates:
		if ids[pixel] == 0:
			if records.size() >= 65535:
				return "Too many disconnected land regions."
			_seed(pixel, distance)
			_grow(land, distance, growth_heights, water.mask_bytes)
	var inland_error := _generate_inland(classes)
	if not inland_error.is_empty(): return inland_error
	return _index_regions()

func build_connections(water: RefCounted) -> void:
	connections.clear()
	if water == null or water.mask_bytes.size() != ids.size() * 4: return
	var seen := {}
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			for next in [i + 1 if x + 1 < size.x else -1, i + size.x if y + 1 < size.y else -1]:
				if next < 0: continue
				var a: int = ids[i]
				var b: int = ids[next]
				if a <= 0 or b <= 0 or a == b: continue
				var low := mini(a, b)
				var high := maxi(a, b)
				var river :Variant= water.mask_bytes[i * 4] > 64 or water.mask_bytes[next * 4] > 64
				var kind := "river_crossing" if river else ("strait" if records[a - 1].kind != records[b - 1].kind else "province_border")
				var key := str(low) + ":" + str(high) + ":" + kind
				if seen.has(key): continue
				seen[key] = true
				connections.append({"a": low, "b": high, "type": kind, "crossings": 1})
	for record in records:
		var parts: int = int(record.get("parts", 1))
		if record.kind == "land" and parts > 1:
			connections.append({"a": record.id, "b": record.id, "type": "island_connection", "crossings": parts - 1})

func _growth_heights(source: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(source.size())
	for y in range(size.y):
		for x in range(size.x):
			var total := 0.0
			var samples := 0
			for oy in range(-1, 2):
				var sy := y + oy
				if sy < 0 or sy >= size.y: continue
				for ox in range(-1, 2):
					var sx := x + ox
					if sx < 0 or sx >= size.x: continue
					total += source[sy * size.x + sx]
					samples += 1
			result[y * size.x + x] = total / float(samples)
	return result

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
	if not impassable.is_empty() and impassable.size() != ids.size(): return "Invalid impassable dimensions."
	for i in range(impassable.size()):
		if impassable[i] > 1 or (impassable[i] != 0 and ids[i] != 0): return "Impassable land cannot own province pixels."
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
	_land_components = _physical_land_labels() if impassable.has(1) else land_components
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
			if regions.has(key) and not (records[id-1].get("kind","land") == "land" and records[id-1].get("allow_fragments",false)): return "A region contains disconnected pieces on the same landmass or ocean."
			regions[key] = true
			part_counts[id - 1] += 1
			if land_components[i] > 0 and _land_components[i] not in mass_lists[id - 1]: mass_lists[id - 1].append(_land_components[i])
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
		records[i].allow_fragments = records[i].get("allow_fragments",false)
		records[i].nation_id = records[i].get("nation_id",0)
		records[i].active = records[i].get("active", true)
		records[i].parts = part_counts[i]
		records[i].landmasses = mass_lists[i]
		records[i].pixels = counts[i]
		records[i].neighbors = []
	for edge in edges:
		records[edge.x - 1].neighbors.append(edge.y)
		records[edge.y - 1].neighbors.append(edge.x)
	for record in records: record.neighbors.sort()
	border_revision += 1
	border_geometry = null
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
			bytes[i * 4 + 2] = 3 if blocked(i) else (2 if ids[i] == 0 and sea_mask.size() == ids.size() and sea_mask[i] != 0 else (1 if ids[i] > 0 and records[ids[i] - 1].get("kind", "land") != "land" else 0))
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
	var blocked_values := PackedFloat32Array()
	blocked_values.resize(impassable.size())
	for i in range(impassable.size()): blocked_values[i] = impassable[i]
	return {"version": 9, "enclosed_seas":enclosed_seas, "inland_generated":inland_generated, "land_includes_sea_datum":land_includes_sea_datum, "nations":nations.duplicate(true), "impassable": Payload.encode(blocked_values) if not blocked_values.is_empty() else null, "coastal_reach": coastal_reach, "sea_mask": Payload.encode(sea_values) if not sea_values.is_empty() else null, "ocean_style": ocean_style, "ocean_generated": ocean_generated, "requested_oceans": requested_oceans, "source_hash": source_hash, "size": [size.x, size.y], "requested_count": requested_count, "ids": Payload.encode(values), "records": records.duplicate(true)}
static func decode(data: Variant) -> Dictionary:
	if data == null: return {"error": "", "layer": null}
	if not data is Dictionary or data.get("version") not in [1, 1.0, 2, 2.0, 3, 3.0, 4, 4.0, 5, 5.0, 6, 6.0, 7, 7.0, 8, 8.0, 9, 9.0] or not data.get("source_hash") is String or data.source_hash.length() != 64 or not data.get("size") is Array or data.size.size() != 2 or not data.get("records") is Array or data.records.size() > 65535:
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
	layer.land_includes_sea_datum = true
	layer.enclosed_seas = false
	if int(data.version) >= 9:
		if not data.get("enclosed_seas") is bool: return {"error":"Invalid enclosed-sea policy."}
		layer.enclosed_seas = data.enclosed_seas
	if int(data.version) >= 8:
		if not data.get("land_includes_sea_datum") is bool: return {"error":"Invalid sea-datum ownership policy."}
		layer.land_includes_sea_datum = data.land_includes_sea_datum
		if not data.get("inland_generated") is bool: return {"error":"Invalid inland-water coverage state."}
		layer.inland_generated = data.inland_generated
	if int(data.version) >= 7:
		if not data.get("nations") is Array or data.nations.size() > 256: return {"error":"Invalid nation palette."}
		for i in range(data.nations.size()):
			var nation: Variant = data.nations[i]
			if not nation is Dictionary or nation.get("id") != i+1 or not nation.get("name") is String or nation.name.strip_edges().is_empty() or nation.name.length() > 128 or not nation.get("color") is Array or nation.color.size() != 3: return {"error":"Invalid nation definition."}
			for channel in nation.color:
				if not (channel is int or channel is float) or not is_finite(float(channel)) or channel < 0 or channel > 1: return {"error":"Invalid nation color."}
			layer.nations.append({"id":i+1,"name":nation.name,"color":nation.color.duplicate()})
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
	if int(data.version) >= 6 and data.get("impassable") != null:
		var blocked_data := Payload.decode(data.impassable, layer.ids.size(), 0, 1)
		if not blocked_data.error.is_empty(): return {"error": blocked_data.error}
		layer.impassable.resize(layer.ids.size())
		for i in range(layer.ids.size()):
			if blocked_data.values[i] != int(blocked_data.values[i]): return {"error": "Invalid impassable mask."}
			layer.impassable[i] = int(blocked_data.values[i])
	var ocean_seen := false
	for i in range(data.records.size()):
		var record: Variant = data.records[i]
		if not record is Dictionary or record.get("id") != i + 1 or not record.get("name") is String or record.name.length() > 128: return {"error": "Invalid province identity."}
		if int(data.version) >= 2 and not record.get("kind", "land") is String: return {"error": "Invalid region kind."}
		var kind: String = record.get("kind", "land") if int(data.version) >= 2 else "land"
		if kind not in ["land", "ocean", "inland_water"] or (kind == "inland_water" and (int(data.version) < 8 or not layer.inland_generated)) or (kind == "land" and ocean_seen and int(data.version) < 5) or (kind == "ocean" and not layer.ocean_generated): return {"error": "Invalid land/ocean region order."}
		ocean_seen = ocean_seen or kind == "ocean"
		if int(data.version) >= 3 and not record.get("active") is bool: return {"error": "Invalid absorbed province state."}
		if int(data.version) >= 6 and not record.get("allow_fragments",false) is bool: return {"error": "Invalid land part policy."}
		var nation: Variant = record.get("nation_id",0) if int(data.version) >= 7 else 0
		if not (nation is int or nation is float) or not is_finite(float(nation)) or nation != int(nation) or nation < 0 or nation > layer.nations.size() or (kind != "land" and nation != 0): return {"error":"Invalid province nation assignment."}
		layer.records.append({"nation_id":int(nation),"allow_fragments":record.get("allow_fragments",false) if int(data.version) >= 6 else false,"id": i + 1, "name": record.name, "pixels": 0, "neighbors": [], "kind": kind, "active": record.get("active", true) if int(data.version) >= 3 else true})
	var error: String = layer._index_regions()
	return {"error": error, "layer": layer}

func validate_coverage(samples: PackedFloat32Array, land_datum: float, water: RefCounted) -> String:
	if samples.size() != ids.size() or water.mask_size != size:
		return "Province coverage dimensions do not match terrain."
	var classes := classify(samples, land_datum, water.mask_bytes, size, land_includes_sea_datum, enclosed_seas)
	var band := coastal_band(classes, size, coastal_reach) if ocean_generated and ocean_style == "coastal_band" else PackedByteArray()
	for i in range(ids.size()):
		var expected: int = classes[i]
		if blocked(i):
			if expected != 1 or ids[i] != 0: return "Impassable zones must remain unassigned land."
			expected = 0
		if ocean_generated and ocean_style == "coastal_band":
			if sea_mask.size() != ids.size() or (sea_mask[i] != 0) != (classes[i] == 2): return "Open ocean mask does not match sea coverage."
			if expected == 2 and band[i] == 0: expected = 0
		if expected == 2 and not ocean_generated: expected = 0
		if expected == 3 and not inland_generated: expected = 0
		var actual := 0 if ids[i] == 0 else (2 if records[ids[i] - 1].kind == "ocean" else (3 if records[ids[i] - 1].kind == "inland_water" else 1))
		if actual != expected: return "Region coverage must keep land, ocean, inland water and generated lakes separate."
	return ""

static func classify(samples: PackedFloat32Array, datum: float, mask: PackedByteArray, dimensions: Vector2i, include_datum_as_land: bool = false, regional_seas: bool = true) -> PackedByteArray:
	# Compare in the source float32 domain, matching the shader sea threshold.
	if not include_datum_as_land: datum = PackedFloat32Array([datum])[0]
	var classes := PackedByteArray()
	classes.resize(samples.size())
	if regional_seas:
		var sea := Seas.mask(samples,dimensions,datum,not include_datum_as_land)
		for i in range(samples.size()):
			# A legacy lake mask cannot turn a sea-level regional sea into a lake.
			if sea[i] == 2 or (sea[i] != 0 and mask[i*4+1] == 0): classes[i] = 2
			elif mask[i*4+1] != 0: classes[i] = 0
			else: classes[i] = 1 if samples[i] > datum or (include_datum_as_land and samples[i] == datum) else 3
		return classes
	var queue := PackedInt32Array()
	for i in range(samples.size()):
		if mask[i * 4 + 1] > 0: continue
		if samples[i] > datum or (include_datum_as_land and samples[i] == datum):
			classes[i] = 1
		elif i < dimensions.x or i >= samples.size() - dimensions.x or i % dimensions.x == 0 or i % dimensions.x == dimensions.x - 1:
			classes[i] = 2
			queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var i := queue[cursor]
		cursor += 1
		for next in [i - 1 if i % dimensions.x > 0 else -1, i + 1 if i % dimensions.x < dimensions.x - 1 else -1, i - dimensions.x, i + dimensions.x]:
			if next >= 0 and next < samples.size() and classes[next] == 0 and (samples[next] < datum or (not include_datum_as_land and samples[next] == datum)) and mask[next * 4 + 1] == 0:
				classes[next] = 2
				queue.append(next)
	for i in range(samples.size()):
		if classes[i] == 0 and mask[i*4+1] == 0: classes[i] = 3
	return classes

func editable_copy() -> RefCounted:
	var copy: RefCounted = load("res://scripts/domain/world_provinces.gd").new()
	copy.source_hash = source_hash
	copy.size = size
	copy.ids = ids.duplicate()
	copy._land_components = _land_components
	copy.records.assign(records.duplicate(true))
	copy.nations.assign(nations.duplicate(true))
	copy.requested_count = requested_count
	copy.ocean_generated = ocean_generated
	copy.inland_generated = inland_generated
	copy.land_includes_sea_datum = land_includes_sea_datum
	copy.enclosed_seas = enclosed_seas
	copy.requested_oceans = requested_oceans
	copy.ocean_style = ocean_style
	copy.coastal_reach = coastal_reach
	copy.sea_mask = sea_mask.duplicate()
	copy.impassable = impassable.duplicate()
	return copy

func generate_oceans(base: PackedFloat32Array, water: RefCounted, count: int = 24, style: String = "coastal_band", reach: float = 64.0) -> String:
	if not is_finite(reach) or reach < 8 or reach > 256 or style not in ["open", "coastal", "coastal_band"] or count < 1 or count > 256 or base.size() != ids.size() or water.mask_size != size: return "Invalid ocean region inputs."
	enclosed_seas = true
	var classes := classify(base, 0.2, water.mask_bytes, size, land_includes_sea_datum, enclosed_seas)
	for i in range(ids.size()):
		if classes[i] == 2 and ids[i] > 0 and records[ids[i]-1].kind == "inland_water": ids[i] = 0
	var inland_error := _generate_inland(classes)
	if not inland_error.is_empty(): return inland_error
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
	if target < 0 or target > records.size() or not a.is_finite() or not b.is_finite() or not is_finite(radius) or radius <= 0: return
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
			if target == 0:
				if previous == 0 or records[previous - 1].kind != "land": continue
				if impassable.is_empty(): impassable.resize(ids.size())
				records[previous-1].allow_fragments = true
				impassable[i] = 1
			else:
				if previous == target: continue
				if previous == 0:
					if not blocked(i) or records[target - 1].kind != "land": continue
				elif records[previous - 1].kind != records[target - 1].kind: continue
				if blocked(i):
					records[target-1].allow_fragments = true
					impassable[i] = 0
			if target > 0 and previous > 0 and attach_islands and records[target - 1].kind == "land" and _land_components.size() == ids.size() and _land_components[i] not in records[target - 1].get("landmasses", []):
				islands[_land_components[i]] = true
			if not changes.has(i): changes[i] = previous
			ids[i] = target
			if _image != null: _image.set_pixel(x, y, _id_color(target, i))
	if not islands.is_empty():
		for i in range(ids.size()):
			if ids[i] > 0 and islands.has(_land_components[i]) and ids[i] != target:
				if not changes.has(i): changes[i] = ids[i]
				ids[i] = target
				if _image != null: _image.set_pixel(i % size.x, i / size.x, _id_color(target, i))
	if _texture != null: _texture.update(_image)

func _id_color(id: int, pixel: int = -1) -> Color:
	if id == 0: return Color8(0,0,3 if pixel >= 0 and blocked(pixel) else 0,255)
	return Color8(id & 255, (id >> 8) & 255, 1 if records[id - 1].kind != "land" else 0, 255)

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
		if part[pixel] == 0: return {"error": "Split one connected land/sea part at a time."}
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
	records.append({"id": new_id, "name": records[id - 1].name.left(108) + " split " + str(new_id), "kind": records[id - 1].kind, "nation_id": records[id-1].get("nation_id",0), "active": true})
	_texture = null
	_image = null
	return {"error": "", "changes": changes, "new_id": new_id}

func blocked(pixel: int) -> bool:
	return impassable.size() == ids.size() and impassable[pixel] != 0
func is_impassable(uv: Vector2) -> bool:
	var p := Vector2i((uv.clamp(Vector2.ZERO,Vector2.ONE) * Vector2(size-Vector2i.ONE)).round())
	return blocked(p.y*size.x+p.x)
func _physical_land_labels() -> PackedInt32Array:
	var labels := PackedInt32Array()
	labels.resize(ids.size())
	var component := 0
	for i in range(ids.size()):
		if labels[i] != 0 or not (blocked(i) or (ids[i] > 0 and records[ids[i]-1].kind == "land")): continue
		component += 1
		var queue := PackedInt32Array([i])
		labels[i] = component
		var cursor := 0
		while cursor < queue.size():
			var pixel := queue[cursor]
			cursor += 1
			for next in _neighbors(pixel):
				if labels[next] == 0 and (blocked(next) or (ids[next] > 0 and records[ids[next]-1].kind == "land")):
					labels[next] = component
					queue.append(next)
	return labels

func add_nation(title: String,color: Color) -> int:
	title = title.strip_edges()
	if title.is_empty() or title.length() > 128 or nations.size() >= 256 or not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b): return 0
	var id := nations.size()+1
	nations.append({"id":id,"name":title,"color":[clampf(color.r,0,1),clampf(color.g,0,1),clampf(color.b,0,1)]})
	border_revision += 1
	return id
func assign_nation(province: int,nation: int) -> String:
	if province < 1 or province > records.size() or not records[province-1].active or records[province-1].kind != "land" or nation < 0 or nation > nations.size(): return "Select an active land province and a valid nation."
	records[province-1].nation_id = nation
	border_revision += 1
	return ""
func nation_color(id: int) -> Color:
	if id <= 0 or id > nations.size(): return Color(0,0,0,0)
	var c: Array = nations[id-1].color
	return Color(c[0],c[1],c[2],1)

# One connected region per enclosed low-elevation basin, independently of coastal
# reach. Existing basin identities survive an ocean-only regeneration.
func _generate_inland(classes: PackedByteArray) -> String:
	for i in range(ids.size()):
		if classes[i] != 3 or ids[i] != 0: continue
		if records.size() >= 65535: return "Too many inland-water regions."
		var id := records.size()+1
		records.append({"id":id,"name":"Inland water "+str(id),"kind":"inland_water","active":true,"nation_id":0})
		var queue := PackedInt32Array([i])
		ids[i] = id
		var cursor := 0
		while cursor < queue.size():
			var pixel := queue[cursor]
			cursor += 1
			for next in _neighbors(pixel):
				if classes[next] == 3 and ids[next] == 0:
					ids[next] = id
					queue.append(next)
	inland_generated = true
	_texture = null
	_image = null
	return ""
