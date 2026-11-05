extends RefCounted
## Seeded, bounded climate proxy shared by Terrain3D ground tint and runoff.
## Fields are unitless runoff, estimated temperature, and regional moisture.
const SIZE := 128
var runoff: Image
var colors: Image

func generate(heights: Image, sea: float, seed_text: String, rainfall: float, warmth: float, wind_degrees: float) -> void:
	runoff = Image.create(SIZE, SIZE, false, Image.FORMAT_RF)
	colors = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = seed_text.hash()
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var wind := Vector2.from_angle(deg_to_rad(wind_degrees))
	for y in range(SIZE):
		for x in range(SIZE):
			var uv := (Vector2(x, y) + Vector2.ONE * 0.5) / SIZE
			var height := _sample(heights, uv)
			var altitude := maxf(0, height - sea) / maxf(0.001, 1 - sea)
			var latitude := lerpf(70, -50, uv.y)
			var temperature := 30.0 - absf(latitude) * 0.55 - altitude * 35.0 + warmth
			var barrier := 0.0
			for distance in [0.02, 0.05, 0.10]:
				barrier = maxf(barrier, _sample(heights, uv - wind * distance) - height)
			var moisture := clampf((0.65 + noise.get_noise_2d(x, y) * 0.3) * (1.0 - minf(0.85, barrier * 4.0)), 0, 1)
			var available := clampf(rainfall * moisture - maxf(0, temperature) * 0.004, 0, 1)
			runoff.set_pixel(x, y, Color(available, 0, 0))
			var dry := Color(0.83, 0.72, 0.53)
			var wet := Color(0.67, 0.80, 0.66)
			var tint := dry.lerp(wet, available)
			tint = tint.lerp(Color(0.82, 0.80, 0.76), smoothstep(0.25, 0.65, altitude))
			tint *= 0.92 + noise.get_noise_2d(x + 317, y - 197) * 0.08
			tint.a = 0.5 # Terrain3D color alpha is neutral wetness, not coverage.
			colors.set_pixel(x, y, tint)

static func _sample(image: Image, uv: Vector2) -> float:
	var position := Vector2i((uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(image.get_size() - Vector2i.ONE)).round())
	return image.get_pixelv(position).r
