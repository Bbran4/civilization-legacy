extends RefCounted
## First-pass terrain-derived province identities.

var field: Image
var texture: ImageTexture
var ids := PackedInt32Array()
var map_size := Vector2.ZERO
var raster_size := Vector2i.ZERO

func generate(graph: RefCounted, world_size: Vector2, requested_resolution: int = 512) -> void:
	map_size = world_size
	raster_size = Vector2i(clampi(requested_resolution, 128, 1024), 0)
	raster_size.y = maxi(64, roundi(float(raster_size.x) * world_size.y / maxf(world_size.x, 1.0)))
	field = Image.create(raster_size.x, raster_size.y, false, Image.FORMAT_RGBA8)
	ids.resize(graph.count)
	for cell in range(graph.count):
		ids[cell] = cell + 1
	for y in range(raster_size.y):
		for x in range(raster_size.x):
			var p := Vector2(float(x) / maxf(1.0, raster_size.x - 1.0) * world_size.x, float(y) / maxf(1.0, raster_size.y - 1.0) * world_size.y)
			var cell: int = graph.nearest_cell(p)
			var c := _province_color(cell)
			c.a = 1.0 if cell < graph.count and graph.heights[cell] >= 20 else 0.0
			field.set_pixel(x, y, c)
	field.generate_mipmaps()
	texture = ImageTexture.create_from_image(field)

func _province_color(cell: int) -> Color:
	var value: int = (cell + 1) * 1103515245 + 12345
	value = absi(value)
	return Color(0.35 + float(value & 255) / 255.0 * 0.55, 0.35 + float((value >> 8) & 255) / 255.0 * 0.55, 0.35 + float((value >> 16) & 255) / 255.0 * 0.55, 1.0)

func snapshot() -> Dictionary:
	return {"version": 1, "generator": "terrain-cell-v1", "cell_count": ids.size(), "raster_size": [raster_size.x, raster_size.y]}
