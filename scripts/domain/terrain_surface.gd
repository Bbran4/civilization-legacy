extends RefCounted
## Rebuildable ground cache. Base heights and hydraulic records are immutable inputs.
const Payload = preload("res://scripts/storage/float_payload.gd")
const DEFAULTS = {"river_depth": 0.006, "lake_depth": 0.012, "bank_width": 3.0}
var source_hash := ""
var water_hash := ""
var size := Vector2i.ZERO
var heights := PackedFloat32Array()
var settings := DEFAULTS.duplicate()
var modified_pixels := 0
var _fingerprint := ""
var _texture: ImageTexture

func build(base: PackedFloat32Array, dimensions: Vector2i, fingerprint: String, water: RefCounted, choices: Dictionary = {}) -> String:
	if water == null or not water.has_hydraulic_data():
		return "Regenerate rivers / lakes to add water elevations before building terrain."
	if water.source_hash != fingerprint or water.mask_size != dimensions or base.size() != dimensions.x * dimensions.y:
		return "Generate rivers / lakes for the current heightmap first."
	var hydraulics: String = water.validate_hydraulics()
	if not hydraulics.is_empty():
		return hydraulics
	settings = DEFAULTS.duplicate()
	settings.merge(choices, true)
	var error := validate_settings(settings)
	if not error.is_empty():
		return error
	source_hash = fingerprint
	water_hash = water.hydraulic_fingerprint()
	size = dimensions
	heights = base.duplicate()
	modified_pixels = 0
	_texture = null
	_fingerprint = ""
	var radius := maxf(1.5, float(settings.bank_width) * maxi(size.x, size.y) / 1025.0)
	var distance := PackedFloat32Array()
	var levels: PackedFloat32Array = water.surface_levels.duplicate()
	distance.resize(base.size())
	for i in range(base.size()):
		var wet: bool = water.mask_bytes[i * 4] > 0 or water.mask_bytes[i * 4 + 1] > 0
		distance[i] = 0.0 if wet else radius + 2.0
		if wet and (levels[i] < 0 or not is_finite(levels[i])):
			return "Water coverage is missing a valid elevation."
	# Two chamfer sweeps propagate water elevations only through the bank corridor.
	for forward in [true, false]:
		var first := 0 if forward else base.size() - 1
		var last := base.size() if forward else -1
		var step := 1 if forward else -1
		for i in range(first, last, step):
			var x := i % size.x
			var y := i / size.x
			var neighbours: Array[int] = []
			if (x > 0 if forward else x < size.x - 1):
				neighbours.append(i - step)
			if (y > 0 if forward else y < size.y - 1):
				neighbours.append(i - step * size.x)
			for next in neighbours:
				var candidate: float = distance[next] + 1.0
				if candidate < distance[i] and candidate <= radius:
					distance[i] = candidate
					levels[i] = levels[next]
	for i in range(base.size()):
		var river: float = water.mask_bytes[i * 4] / 255.0
		var lake: bool = water.mask_bytes[i * 4 + 1] > 0
		if lake or river > 0:
			var depth: float = settings.lake_depth if lake else settings.river_depth * lerpf(0.2, 1.0, river)
			heights[i] = clampf(minf(base[i], levels[i] - depth), 0, 1)
		elif distance[i] <= radius and base[i] >= 0.2:
			var t := clampf(distance[i] / radius, 0, 1)
			var bank: float = levels[i] + 0.001 + distance[i] * 0.0005
			heights[i] = clampf(lerpf(bank, base[i], smoothstep(0, 1, t)), 0, 1)
			# Keep the immediate dry shore above every adjacent water level.
			var x := i % size.x
			for next in [i - 1 if x > 0 else -1, i + 1 if x < size.x - 1 else -1, i - size.x, i + size.x]:
				if next >= 0 and next < base.size() and water.surface_levels[next] >= 0:
					heights[i] = maxf(heights[i], minf(1, water.surface_levels[next] + 0.001))
		if heights[i] != base[i]:
			modified_pixels += 1
	return ""

static func validate_settings(value: Variant) -> String:
	if not value is Dictionary or value.size() != DEFAULTS.size():
		return "Invalid terrain surface settings."
	for key in DEFAULTS:
		var v: Variant = value.get(key)
		var low := 1.0 if key == "bank_width" else 0.001
		var high := 12.0 if key == "bank_width" else 0.05
		if not (v is int or v is float) or not is_finite(float(v)) or v < low or v > high:
			return "Invalid terrain surface setting: " + key
	return ""

func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, heights.to_byte_array()))
	return _texture

func export_image() -> Image:
	var result := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, heights.to_byte_array())
	result.convert(Image.FORMAT_RGB8)
	return result

func snapshot() -> Dictionary:
	return {"version": 1, "source_hash": source_hash, "water_hash": water_hash, "size": [size.x, size.y], "settings": settings.duplicate(), "heights": Payload.encode(heights), "modified_pixels": modified_pixels}

static func decode(data: Variant) -> Dictionary:
	if data == null:
		return {"error": "", "layer": null}
	if not data is Dictionary or data.get("version") != 1 or not data.get("source_hash") is String or data.source_hash.length() != 64 or not data.get("water_hash") is String or data.water_hash.length() != 64 or not data.get("size") is Array or data.size.size() != 2:
		return {"error": "Invalid terrain surface cache."}
	for v in data.size:
		if not (v is int or v is float) or not is_finite(float(v)) or v != int(v) or v < 3 or v > 4096:
			return {"error": "Invalid terrain surface dimensions."}
	var error := validate_settings(data.get("settings"))
	if not error.is_empty():
		return {"error": error}
	var payload := Payload.decode(data.get("heights"), int(data.size[0]) * int(data.size[1]), 0, 1)
	if not payload.error.is_empty():
		return {"error": payload.error}
	var layer: RefCounted = load("res://scripts/domain/terrain_surface.gd").new()
	layer.source_hash = data.source_hash
	layer.water_hash = data.water_hash
	layer.size = Vector2i(data.size[0], data.size[1])
	layer.settings = data.settings.duplicate()
	layer.heights = payload.values
	var count: Variant = data.get("modified_pixels", 0)
	if not (count is int or count is float) or not is_finite(float(count)) or count != int(count) or count < 0 or count > layer.heights.size():
		return {"error": "Invalid terrain surface statistics."}
	layer.modified_pixels = int(count)
	return {"error": "", "layer": layer}

func validate_water(water: RefCounted) -> String:
	if water == null or not water.has_hydraulic_data() or water_hash != water.hydraulic_fingerprint() or size != water.mask_size:
		return "" # Retain stale caches without presenting them as current.
	for i in range(heights.size()):
		if water.surface_levels[i] >= 0 and heights[i] >= water.surface_levels[i]:
			return "Terrain surface contains an exposed water bed. Rebuild it."
	return ""

func fingerprint() -> String:
	if _fingerprint.is_empty():
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update((source_hash + water_hash).to_utf8_buffer())
		context.update(heights.to_byte_array())
		_fingerprint = context.finish().hex_encode()
	return _fingerprint
