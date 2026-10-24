extends RefCounted
## One owner for the first-pass annual climate-to-biome rules and palette.
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const NAMES: Array[String] = ["Marine", "Ice", "Tundra", "Cold desert", "Hot desert", "Steppe", "Grassland", "Savanna", "Boreal forest", "Temperate forest", "Temperate rainforest", "Tropical rainforest"]
const COLORS: Array[Color] = [Color("285b70"), Color("e4edf0"), Color("9b9980"), Color("b0a28a"), Color("d8b772"), Color("b6a369"), Color("8f9c58"), Color("a8a35b"), Color("486b5a"), Color("4d7947"), Color("306854"), Color("245d36")]
var ids := PackedByteArray()
var size := Vector2i.ZERO
const PALETTE_SIZE := Vector2i(281, 601) # 0.5°C by 10 mm/year.
static var _palette: Image
var image: Image
var generation_ms: float = 0.0


static func moisture_ratio(temperature: float, rainfall: float) -> float:
	# Annual evaporative-demand proxy in mm, not a hydrological PET solution.
	return rainfall / maxf(150.0, 400.0 + maxf(-5.0, temperature) * 45.0)


static func classify(temperature: float, rainfall: float, land: bool = true) -> int:
	if not land:
		return 0
	if temperature < -12.0:
		return 1
	if temperature < 2.0:
		return 2
	var moisture: float = moisture_ratio(temperature, rainfall)
	if rainfall < 150.0 or moisture < 0.20:
		return 4 if temperature >= 18.0 else 3
	if moisture < 0.45:
		return 5
	if temperature >= 20.0:
		return 11 if rainfall >= 1800.0 else 7
	if temperature < 8.0:
		return 8 if moisture >= 0.75 else 6
	if rainfall >= 2000.0:
		return 10
	return 9 if moisture >= 0.85 else 6


func generate(climate: RefCounted, geography: RefCounted) -> void:
	var started: int = Time.get_ticks_usec()
	size = climate.size
	ids.resize(size.x * size.y)
	image = palette_image()
	for y in range(size.y):
		for x in range(size.x):
			var i: int = y * size.x + x
			var height: float = Grid.sample(geography.display_heights, geography.contour_size, Vector2(x, y) / Vector2(size - Vector2i.ONE))
			var id: int = classify(climate.temperature[i], climate.rainfall[i], height >= 0.2)
			ids[i] = id
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0


static func cell_info(temperature: float, rainfall: float, land: bool) -> Dictionary:
	var id: int = classify(temperature, rainfall, land)
	return {"biome_id": id, "biome": NAMES[id], "moisture_ratio": moisture_ratio(temperature, rainfall)}


static func palette_image() -> Image:
	if _palette != null:
		return _palette
	_palette = Image.create(PALETTE_SIZE.x, PALETTE_SIZE.y, false, Image.FORMAT_RGBA8)
	for y in range(PALETTE_SIZE.y):
		for x in range(PALETTE_SIZE.x):
			var temperature: float = -80.0 + x * 0.5
			var rainfall: float = y * 10.0
			_palette.set_pixel(x, y, COLORS[classify(temperature, rainfall, true)])
	_palette = _soften_palette(_palette)
	return _palette


static func _soften_palette(source: Image) -> Image:
	var weights: Array[float] = [1.0, 4.0, 6.0, 4.0, 1.0]
	for axis in range(2):
		var target := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				var color := Color(0, 0, 0, 0)
				for tap in range(-2, 3):
					var sx: int = clampi(x + (tap if axis == 0 else 0), 0, source.get_width() - 1)
					var sy: int = clampi(y + (tap if axis == 1 else 0), 0, source.get_height() - 1)
					color += source.get_pixel(sx, sy) * weights[tap + 2] / 16.0
				target.set_pixel(x, y, color)
		source = target
	return source
