extends RefCounted
## A shared, seeded appearance field. Never feeds height, hydrology or provinces.
## Channels: lowland warmth / regional moisture. CPU reads the same quantized
## texels and center-based interpolation as the GPU, not a second noise model.
const SIZE = 128
const LAPSE = 0.65
const SNOW_COOLING = 0.14
var seed_text: String
var key := ""
var texture: ImageTexture
var _bytes := PackedByteArray()
var _raw := PackedByteArray()
var _variation := 0
func _init(world_seed: String, variation: int = 0, warmth_offset: float = 0, moisture_offset: float = 0, overrides: PackedByteArray = PackedByteArray()) -> void:
	seed_text = world_seed
	_variation = variation
	key = world_seed+"/"+str(variation)
	var warmth := _noise("warmth")
	var rain := _noise("rain")
	var image := Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	for y in range(SIZE):
		for x in range(SIZE):
			var uv := (Vector2(x,y)+Vector2.ONE*0.5)/SIZE
			var temperature := clampf(0.96-absf(uv.y-0.5)*1.65+warmth.get_noise_2dv(uv*3.0)*0.24,0.05,0.98)
			var moisture := clampf(0.5+rain.get_noise_2dv(uv*4.0)*0.9,0.05,0.95)
			var i := (y*SIZE+x)*4
			if overrides.size() == SIZE*SIZE*4 and overrides[i+3] != 0:
				temperature = overrides[i]/255.0
				moisture = overrides[i+1]/255.0
			image.set_pixel(x,y,Color(temperature,moisture,0,1))
	_raw = image.get_data()
	for y in range(SIZE):
		for x in range(SIZE):
			var value := image.get_pixel(x,y)
			image.set_pixel(x,y,Color(clampf(value.r+warmth_offset/100.0,0,1),clampf(value.g+moisture_offset/100.0,0,1),0,1))
	_bytes = image.get_data()
	texture = ImageTexture.create_from_image(image)
func _noise(channel: String) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = int((seed_text+"/regions/"+channel+("/"+str(_variation) if _variation != 0 else "")).hash() & 0x7fffffff)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	return noise
func sample(uv: Vector2, height: float) -> Vector2:
	var p := (uv*SIZE-Vector2.ONE*0.5).clamp(Vector2.ZERO,Vector2.ONE*(SIZE-1))
	var cell := Vector2i(p).min(Vector2i(SIZE-2,SIZE-2))
	var f := p-Vector2(cell)
	var value := _at(cell).lerp(_at(cell+Vector2i.RIGHT),f.x).lerp(_at(cell+Vector2i.DOWN).lerp(_at(cell+Vector2i.ONE),f.x),f.y)
	value.x = clampf(value.x-maxf(0.0,height-0.2)*LAPSE,0.0,1.0)
	return value
func _at(cell: Vector2i) -> Vector2:
	var index := (cell.y*SIZE+cell.x)*4
	return Vector2(_bytes[index],_bytes[index+1])/255.0
