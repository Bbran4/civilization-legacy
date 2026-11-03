extends RefCounted
## Independently generated water artwork. Routing elevations never edit terrain.
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const DEFAULTS = {"routing_resolution": 513, "density": 1.0, "width": 1.5, "lake_depth": 0.01, "lake_area": 0.01}
const RIVER_COLOR = Color("397fa8")
const LAKE_COLOR = Color("286789")
const SEA = 0.2
var source_hash := ""
var settings: Dictionary = DEFAULTS.duplicate()
var mask_size := Vector2i.ZERO
var routing_size := Vector2i.ZERO
var mask_bytes := PackedByteArray()
var river_reaches := 0
var lake_count := 0
var downstream := PackedInt32Array()
var filled := PackedFloat32Array()
var bed := PackedFloat32Array()
var flow := PackedFloat32Array()
var ocean := PackedByteArray()
var lake_ids := PackedInt32Array()
var lakes: Array[Dictionary] = []
var _seen := PackedByteArray()
var _heap: Array[int] = []
var _order := PackedInt32Array()
var _image: Image
var _texture: Texture2D

static func validate_settings(value: Variant) -> String:
	if not value is Dictionary:
		return "Missing water settings."
	var routing: Variant = value.get("routing_resolution")
	if not (routing is int or routing is float) or not is_finite(float(routing)) or routing != int(routing) or int(routing) not in [257, 513, 1025]:
		return "Choose 257, 513 or 1025 drainage samples."
	for key in ["density", "width", "lake_depth", "lake_area"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)):
			return "Invalid water setting: " + key
	if value.density < 0.25 or value.density > 4 or value.width < 0.5 or value.width > 8 or value.lake_depth < 0.002 or value.lake_depth > 0.1 or value.lake_area < 0.001 or value.lake_area > 1:
		return "Water settings are out of range."
	return ""

static func fingerprint(samples: PackedFloat32Array, size: Vector2i, extent: Vector2, offset: float, elevation: float, version: int) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(samples.to_byte_array())
	context.update(JSON.stringify([size.x, size.y, extent.x, extent.y, offset, elevation, version]).to_utf8_buffer())
	return context.finish().hex_encode()

func generate(heights: PackedFloat32Array, size: Vector2i, source: String, choices: Dictionary) -> String:
	var error := validate_settings(choices)
	if not error.is_empty():
		return error
	if size.x < 3 or size.y < 3 or maxi(size.x, size.y) > 2050 or heights.size() != size.x * size.y:
		return "Unsupported heightmap size for water generation."
	lakes.clear()
	lake_count = 0
	river_reaches = 0
	_image = null
	_texture = null
	source_hash = source
	settings = choices.duplicate()
	mask_size = size
	# Keep drainage work bounded, while always rasterizing the final water at full output resolution.
	var longest := mini(int(settings.routing_resolution), maxi(size.x, size.y))
	routing_size = Grid.sample_size_for(Vector2(size - Vector2i.ONE), longest - 1)
	bed.resize(routing_size.x * routing_size.y)
	for y in range(routing_size.y):
		for x in range(routing_size.x):
			bed[y * routing_size.x + x] = Grid.sample(heights, size, Vector2(x, y) / Vector2(routing_size - Vector2i.ONE))
	_route()
	_find_lakes()
	mask_bytes.resize(size.x * size.y * 4)
	mask_bytes.fill(0)
	_draw_lakes(heights)
	_draw_rivers(heights)
	return ""

func _neighbors(cell: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var x := cell % routing_size.x
	var y := cell / routing_size.x
	for dy in range(maxi(0, y - 1), mini(routing_size.y, y + 2)):
		for dx in range(maxi(0, x - 1), mini(routing_size.x, x + 2)):
			var neighbor := dy * routing_size.x + dx
			if neighbor != cell:
				result.append(neighbor)
	return result

func _push(cell: int) -> void:
	_heap.append(cell)
	var i := _heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		var other := _heap[parent]
		if filled[other] < filled[cell] or (filled[other] == filled[cell] and other < cell):
			break
		_heap[i] = other
		i = parent
	_heap[i] = cell

func _pop() -> int:
	var result := _heap[0]
	var last: int = _heap.pop_back()
	if _heap.is_empty():
		return result
	var i := 0
	while i * 2 + 1 < _heap.size():
		var child := i * 2 + 1
		if child + 1 < _heap.size():
			var a := _heap[child]
			var b := _heap[child + 1]
			if filled[b] < filled[a] or (filled[b] == filled[a] and b < a):
				child += 1
		var next := _heap[child]
		if filled[last] < filled[next] or (filled[last] == filled[next] and last < next):
			break
		_heap[i] = next
		i = child
	_heap[i] = last
	return result

func _route() -> void:
	var count := bed.size()
	filled = bed.duplicate()
	downstream.resize(count)
	downstream.fill(-1)
	ocean.resize(count)
	ocean.fill(0)
	var queue := PackedInt32Array()
	for y in range(routing_size.y):
		for x in range(routing_size.x):
			var i := y * routing_size.x + x
			if (x == 0 or y == 0 or x == routing_size.x - 1 or y == routing_size.y - 1) and bed[i] < SEA:
				ocean[i] = 1
				queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var i := queue[cursor]
		cursor += 1
		for neighbor in _neighbors(i):
			if ocean[neighbor] == 0 and bed[neighbor] < SEA:
				ocean[neighbor] = 1
				queue.append(neighbor)
	_seen = ocean.duplicate()
	_heap.clear()
	_order.clear()
	for i in range(count):
		if ocean[i] != 0:
			filled[i] = SEA
			continue
		var x := i % routing_size.x
		var y := i / routing_size.x
		if x == 0 or y == 0 or x == routing_size.x - 1 or y == routing_size.y - 1:
			_seen[i] = 1
			_push(i)
		else:
			for neighbor in _neighbors(i):
				if ocean[neighbor] != 0:
					filled[i] = maxf(bed[i], SEA)
					downstream[i] = neighbor
					_seen[i] = 1
					_push(i)
					break
	while not _heap.is_empty():
		var i := _pop()
		_order.append(i)
		for neighbor in _neighbors(i):
			if _seen[neighbor] != 0:
				continue
			_seen[neighbor] = 1
			filled[neighbor] = maxf(bed[neighbor], filled[i])
			downstream[neighbor] = i
			_push(neighbor)
	# True descents take precedence over priority-flood flat routing.
	for i in _order:
		var steepest := 0.0
		for neighbor in _neighbors(i):
			var distance := 1.41421356 if neighbor % routing_size.x != i % routing_size.x and neighbor / routing_size.x != i / routing_size.x else 1.0
			var slope := (filled[i] - filled[neighbor]) / distance
			if slope > steepest:
				steepest = slope
				downstream[i] = neighbor
	flow.resize(count)
	flow.fill(1.0)
	for j in range(_order.size() - 1, -1, -1):
		var i := _order[j]
		if downstream[i] >= 0:
			flow[downstream[i]] += flow[i]

func _find_lakes() -> void:
	lake_ids.resize(bed.size())
	lake_ids.fill(-1)
	var seen := PackedByteArray()
	seen.resize(bed.size())
	var minimum_area := maxi(4, ceili(bed.size() * float(settings.lake_area) / 100.0))
	for i in range(bed.size()):
		if seen[i] != 0 or ocean[i] != 0 or filled[i] - bed[i] <= 0.00001:
			continue
		var cells := PackedInt32Array([i])
		seen[i] = 1
		var cursor := 0
		var depth := 0.0
		while cursor < cells.size():
			var cell := cells[cursor]
			cursor += 1
			depth = maxf(depth, filled[cell] - bed[cell])
			for neighbor in _neighbors(cell):
				if seen[neighbor] == 0 and ocean[neighbor] == 0 and filled[neighbor] - bed[neighbor] > 0.00001 and absf(filled[neighbor] - filled[i]) < 0.000001:
					seen[neighbor] = 1
					cells.append(neighbor)
		if cells.size() < minimum_area or depth < float(settings.lake_depth):
			continue
		var id := lakes.size()
		for cell in cells:
			lake_ids[cell] = id
		lakes.append({"level": filled[i], "cells": cells, "depth": depth})
	lake_count = lakes.size()

func _point(cell: int) -> Vector2:
	return Vector2(cell % routing_size.x, cell / routing_size.x) * Vector2(mask_size - Vector2i.ONE) / Vector2(routing_size - Vector2i.ONE)

func _draw_rivers(heights: PackedFloat32Array) -> void:
	var threshold := maxf(8.0, _order.size() * 0.0012 / float(settings.density))
	var selected := PackedByteArray()
	selected.resize(bed.size())
	var donors := PackedInt32Array()
	donors.resize(bed.size())
	var lake_donor := PackedInt32Array()
	lake_donor.resize(bed.size())
	lake_donor.fill(-1)
	for i in _order:
		selected[i] = 1 if flow[i] >= threshold and lake_ids[i] < 0 and downstream[i] >= 0 else 0
	for i in _order:
		var next := downstream[i]
		if next >= 0 and selected[i] != 0:
			donors[next] += 1
		if next >= 0 and lake_ids[i] >= 0:
			lake_donor[next] = i
	for start in _order:
		if selected[start] == 0 or donors[start] == 1:
			continue
		var points := PackedVector2Array()
		var widths := PackedFloat32Array()
		if lake_donor[start] >= 0:
			points.append(_point(lake_donor[start]))
			widths.append(_river_width(flow[start], threshold))
		points.append(_point(start))
		widths.append(_river_width(flow[start], threshold))
		var cell := start
		while downstream[cell] >= 0:
			var next := downstream[cell]
			points.append(_point(next))
			widths.append(_river_width(flow[next], threshold))
			if selected[next] == 0 or donors[next] != 1:
				break
			cell = next
		if points.size() < 2:
			continue
		river_reaches += 1
		# Corner-cutting keeps confluence endpoints shared, without right-angle raster stairs.
		var smooth := PackedVector2Array([points[0]])
		var smooth_width := PackedFloat32Array([widths[0]])
		for j in range(points.size() - 1):
			smooth.append(points[j].lerp(points[j + 1], 0.25))
			smooth.append(points[j].lerp(points[j + 1], 0.75))
			smooth_width.append(lerpf(widths[j], widths[j + 1], 0.25))
			smooth_width.append(lerpf(widths[j], widths[j + 1], 0.75))
		smooth.append(points[-1])
		smooth_width.append(widths[-1])
		for j in range(smooth.size() - 1):
			_capsule(smooth[j], smooth[j + 1], smooth_width[j], smooth_width[j + 1], heights)

func _river_width(discharge: float, threshold: float) -> float:
	return maxf(0.75, float(settings.width) * float(maxi(mask_size.x, mask_size.y)) / 1025.0 * clampf(pow(maxf(1.0, discharge / threshold), 0.3), 1.0, 5.0))

func _capsule(a: Vector2, b: Vector2, width_a: float, width_b: float, heights: PackedFloat32Array) -> void:
	var radius := maxf(width_a, width_b) * 0.5 + 1.0
	var low := Vector2i((a.min(b) - Vector2.ONE * radius).floor()).max(Vector2i.ZERO)
	var high := Vector2i((a.max(b) + Vector2.ONE * radius).ceil()).min(mask_size - Vector2i.ONE)
	var delta := b - a
	var length_squared := delta.length_squared()
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var i := y * mask_size.x + x
			if heights[i] < SEA:
				continue
			var p := Vector2(x, y)
			var t := clampf((p - a).dot(delta) / length_squared, 0, 1) if length_squared > 0.00001 else 0.0
			var coverage := clampf(lerpf(width_a, width_b, t) * 0.5 + 0.5 - p.distance_to(a + delta * t), 0, 1)
			var value := int(roundf(coverage * 255))
			mask_bytes[i * 4] = maxi(mask_bytes[i * 4], value)
			mask_bytes[i * 4 + 3] = maxi(mask_bytes[i * 4 + 3], value)

func _draw_lakes(heights: PackedFloat32Array) -> void:
	# Re-flood each candidate against the full saved raster. Its shore is a real
	# height contour, not enlarged drainage-grid squares or graph triangles.
	var visited := PackedInt32Array()
	visited.resize(heights.size())
	lake_count = 0
	var minimum_area := maxi(4, ceili(heights.size() * float(settings.lake_area) / 100.0))
	for id in range(lakes.size()):
		var lake: Dictionary = lakes[id]
		var low := mask_size - Vector2i.ONE
		var high := Vector2i.ZERO
		var deepest: int = lake.cells[0]
		for cell in lake.cells:
			var point := Vector2i(_point(cell).round())
			low = low.min(point)
			high = high.max(point)
			if bed[cell] < bed[deepest]:
				deepest = cell
		var margin := Vector2i((Vector2(mask_size) / Vector2(routing_size) * 3.0).ceil())
		low = (low - margin).max(Vector2i.ZERO)
		high = (high + margin).min(mask_size - Vector2i.ONE)
		var seed_point := Vector2i(_point(deepest).round())
		var seed := seed_point.y * mask_size.x + seed_point.x
		for y in range(maxi(0, seed_point.y - 1), mini(mask_size.y, seed_point.y + 2)):
			for x in range(maxi(0, seed_point.x - 1), mini(mask_size.x, seed_point.x + 2)):
				if heights[y * mask_size.x + x] < heights[seed]:
					seed = y * mask_size.x + x
		var escaped := false
		var pixels := PackedInt32Array()
		if heights[seed] < float(lake.level) - float(settings.lake_depth):
			pixels.append(seed)
			visited[seed] = id + 1
		var cursor := 0
		while cursor < pixels.size() and not escaped:
			var pixel := pixels[cursor]
			cursor += 1
			var x := pixel % mask_size.x
			var y := pixel / mask_size.x
			if x <= low.x or x >= high.x or y <= low.y or y >= high.y:
				escaped = true
				break
			for next in [pixel - 1, pixel + 1, pixel - mask_size.x, pixel + mask_size.x]:
				if visited[next] != id + 1 and heights[next] < float(lake.level) - 0.00001:
					visited[next] = id + 1
					pixels.append(next)
		if escaped or pixels.size() < minimum_area:
			for cell in lake.cells:
				lake_ids[cell] = -1
			continue
		lake_count += 1
		for pixel in pixels:
			mask_bytes[pixel * 4 + 1] = 255
			mask_bytes[pixel * 4 + 3] = 255

func image() -> Image:
	if _image == null:
		_image = Image.create_from_data(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8, mask_bytes)
	return _image

func texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(image())
	return _texture

func export_image() -> Image:
	var bytes := mask_bytes.duplicate()
	for i in range(0, bytes.size(), 4):
		var colour := LAKE_COLOR if bytes[i + 1] > 0 else RIVER_COLOR
		bytes[i] = roundi(colour.r * 255)
		bytes[i + 1] = roundi(colour.g * 255)
		bytes[i + 2] = roundi(colour.b * 255)
	return Image.create_from_data(mask_size.x, mask_size.y, false, Image.FORMAT_RGBA8, bytes)

func snapshot() -> Dictionary:
	return {"version": 1, "source_hash": source_hash, "settings": settings.duplicate(), "size": [mask_size.x, mask_size.y], "routing_size": [routing_size.x, routing_size.y], "river_reaches": river_reaches, "lakes": lake_count, "png": Marshalls.raw_to_base64(image().save_png_to_buffer())}

static func decode(data: Variant) -> Dictionary:
	if data == null:
		return {"error": "", "layer": null}
	if not data is Dictionary or data.get("version") != 1 or not data.get("source_hash") is String or data.source_hash.length() != 64 or not data.get("png") is String or data.png.length() > 32 * 1024 * 1024:
		return {"error": "Invalid rivers/lakes layer."}
	var error := validate_settings(data.get("settings"))
	if not error.is_empty():
		return {"error": error}
	for key in ["size", "routing_size"]:
		var size: Variant = data.get(key)
		if not size is Array or size.size() != 2:
			return {"error": "Invalid water map dimensions."}
		for value in size:
			if not (value is int or value is float) or not is_finite(float(value)) or value != int(value) or value < 3 or value > (2050 if key == "size" else 1025):
				return {"error": "Invalid water map dimensions."}
	for key in ["river_reaches", "lakes"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value != int(value) or value < 0 or value > 1100000:
			return {"error": "Invalid water feature count."}
	var bytes := Marshalls.base64_to_raw(data.png)
	# Bound PNG dimensions before decompression, including malicious imported documents.
	if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return {"error": "Invalid water mask PNG."}
	var width := (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | int(bytes[19])
	var height := (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | int(bytes[23])
	if width != int(data.size[0]) or height != int(data.size[1]):
		return {"error": "Water mask dimensions do not match its metadata."}
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return {"error": "Could not decode the water mask."}
	image.convert(Image.FORMAT_RGBA8)
	var layer: RefCounted = load("res://scripts/domain/terrain_water_layer.gd").new()
	layer.source_hash = data.source_hash
	layer.settings = data.settings.duplicate()
	layer.mask_size = Vector2i(data.size[0], data.size[1])
	layer.routing_size = Vector2i(data.routing_size[0], data.routing_size[1])
	layer.river_reaches = int(data.river_reaches)
	layer.lake_count = int(data.lakes)
	layer.mask_bytes = image.get_data()
	return {"error": "", "layer": layer}
