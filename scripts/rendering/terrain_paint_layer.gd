extends RefCounted
## A lossless appearance layer, independent from climate, elevation and native biomes.
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
var extent := Vector2.ZERO
var image: Image
var texture: ImageTexture
var history: Array[PackedByteArray] = []

func _init(size: Vector2 = Vector2.ZERO) -> void:
	extent = size

func begin_stroke() -> void:
	history.append(image.save_png_to_buffer() if image != null else PackedByteArray())
	var bytes: int = 0
	for entry in history:
		bytes += entry.size()
	while history.size() > 16 or (bytes > 32 * 1024 * 1024 and history.size() > 1):
		bytes -= history.pop_front().size()

func _publish() -> void:
	if image == null:
		texture = null
	elif texture == null:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)

func stroke(start: Vector2, end: Vector2, radius: float, amount: float, row: int, slot: int = -1, erase: bool = false) -> void:
	if extent.x <= 0 or extent.y <= 0 or radius <= 0 or amount <= 0:
		return
	if image == null:
		var size: Vector2i = Grid.sample_size_for(extent, clampi(ceili(maxf(extent.x, extent.y) * 2.0), 256, 2048))
		image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 1))
	var scale: Vector2 = Vector2(image.get_size() - Vector2i.ONE) / extent
	var low := Vector2i(((start.min(end) - Vector2.ONE * radius) * scale).floor()).max(Vector2i.ZERO)
	var high := Vector2i(((start.max(end) + Vector2.ONE * radius) * scale).ceil()).min(image.get_size() - Vector2i.ONE)
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var point := Vector2(x, y) / scale
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, start, end)
			var coverage: float = (1.0 - smoothstep(radius * 0.55, radius, point.distance_to(closest))) * amount
			if coverage <= 0:
				continue
			var old: Color = image.get_pixel(x, y)
			if erase:
				old.g *= 1.0 - coverage
				image.set_pixel(x, y, old)
			else:
				var strength: float = old.g + (1.0 - old.g) * coverage if roundi(old.r * 255) == row and roundi(old.b * 255) == slot + 1 else coverage
				image.set_pixel(x, y, Color(row / 255.0, strength, (slot + 1) / 255.0, 1))
	_publish()

func undo() -> bool:
	if history.is_empty():
		return false
	var previous: PackedByteArray = history.pop_back()
	if previous.is_empty():
		image = null
		texture = null
	else:
		image = Image.new()
		image.load_png_from_buffer(previous)
		texture = ImageTexture.create_from_image(image)
	return true

func snapshot() -> Dictionary:
	return {"version": 1, "png": Marshalls.raw_to_base64(image.save_png_to_buffer()) if image != null else ""}

func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("ground_paint_enabled", image != null)
	if texture != null:
		material.set_shader_parameter("ground_paint", texture)

static func decode(data: Variant, size: Vector2) -> Dictionary:
	if not data is Dictionary or data.get("version") != 1 or not data.get("png") is String or data.png.length() > 32 * 1024 * 1024:
		return {"ok": false, "error": "Invalid painted-ground layer."}
	var layer: RefCounted = load("res://scripts/rendering/terrain_paint_layer.gd").new(size)
	if data.png.is_empty():
		return {"ok": true, "layer": layer, "error": ""}
	var base64 := RegEx.new()
	base64.compile("^[A-Za-z0-9+/]*={0,2}$")
	if data.png.length() % 4 != 0 or base64.search(data.png) == null:
		return {"ok": false, "error": "Invalid paint image encoding."}
	var bytes: PackedByteArray = Marshalls.base64_to_raw(data.png)
	if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return {"ok": false, "error": "Paint data must be a PNG image."}
	var width: int = (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | bytes[19]
	var height: int = (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | bytes[23]
	var expected: Vector2i = Grid.sample_size_for(size, clampi(ceili(maxf(size.x, size.y) * 2.0), 256, 2048))
	if Vector2i(width, height) != expected:
		return {"ok": false, "error": "Paint image dimensions do not match this map."}
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return {"ok": false, "error": "The painted-ground PNG is damaged."}
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var value: Color = image.get_pixel(x, y)
			if roundi(value.r * 255) > 18 or roundi(value.b * 255) > 3:
				return {"ok": false, "error": "Paint data refers to an unknown material."}
	layer.image = image
	layer._publish()
	return {"ok": true, "layer": layer, "error": ""}
