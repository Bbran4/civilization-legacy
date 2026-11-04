extends RefCounted
## Appearance-only raster. Generation inputs and derived caches never depend on it.
const SIZE = Vector2i(1024, 1024)
var image: Image
var texture: ImageTexture
var undo_images: Array[Image] = []
func _init() -> void:
	image = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	texture = ImageTexture.create_from_image(image)
func begin_stroke() -> void:
	undo_images.append(image.duplicate())
	if undo_images.size() > 16: undo_images.pop_front()
func stamp(uv: Vector2, extent: Vector2, radius: float, color: Color, erase: bool = false) -> void:
	var center := uv * Vector2(SIZE - Vector2i.ONE)
	var pixels := Vector2.ONE * radius / extent * Vector2(SIZE)
	for y in range(maxi(0,floori(center.y-pixels.y)),mini(SIZE.y,ceili(center.y+pixels.y)+1)):
		for x in range(maxi(0,floori(center.x-pixels.x)),mini(SIZE.x,ceili(center.x+pixels.x)+1)):
			var d := ((Vector2(x,y)-center)/pixels).length()
			if d > 1: continue
			var old := image.get_pixel(x,y)
			var strength := (1.0-smoothstep(0.4,1.0,d))*0.65
			if erase:
				old.a *= 1.0-strength
			else:
				var alpha := color.a*strength
				var combined := alpha+old.a*(1.0-alpha)
				var rgb := (Vector3(color.r,color.g,color.b)*alpha+Vector3(old.r,old.g,old.b)*old.a*(1.0-alpha))/maxf(combined,0.00001)
				old = Color(rgb.x,rgb.y,rgb.z,combined)
			image.set_pixel(x,y,old)
func refresh() -> void:
	texture.update(image)
func undo() -> bool:
	if undo_images.is_empty(): return false
	image = undo_images.pop_back()
	refresh()
	return true
func clear() -> void:
	begin_stroke()
	image.fill(Color(0,0,0,0))
	refresh()
func snapshot() -> Dictionary:
	return {"version":1,"png":Marshalls.raw_to_base64(image.save_png_to_buffer())}
static func decode(value: Variant) -> Dictionary:
	var layer = load("res://scripts/domain/map_paint.gd").new()
	if value == null: return {"error":"","layer":layer}
	if not value is Dictionary or value.get("version") != 1 or not value.get("png") is String or value.png.length() > 8*1024*1024: return {"error":"Invalid ground paint.","layer":null}
	var bytes := Marshalls.base64_to_raw(value.png)
	if bytes.size() < 24 or bytes.slice(0,8) != PackedByteArray([137,80,78,71,13,10,26,10]) or bytes.slice(12,16).get_string_from_ascii() != "IHDR" or bytes.slice(16,24) != PackedByteArray([0,0,4,0,0,0,4,0]): return {"error":"Invalid paint image dimensions.","layer":null}
	var decoded := Image.new()
	if decoded.load_png_from_buffer(bytes) != OK: return {"error":"Invalid paint image.","layer":null}
	decoded.convert(Image.FORMAT_RGBA8)
	layer.image = decoded
	layer.refresh()
	return {"error":"","layer":layer}
