@tool
extends RefCounted
## Original procedural surface library. Cached assets are shared by base and LODs.
const Alea = preload("res://scripts/domain/alea.gd")
const Biomes = preload("res://scripts/domain/terrain_biomes.gd")
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const NAMES := ["Grass", "Dry grass", "Soil", "Sand", "Rock", "Snow", "Wet ground"]
const TILE_SIZE := 128
const TILE_WORLD_SIZE := 8.0
static var albedo: Texture2DArray
static var normals: Texture2DArray
static var weights: ImageTexture
static var transition_colors: ImageTexture
static var transition_weights: ImageTexture
static var transition_noise: ImageTexture
static var build_count: int = 0


static func _hash(x: int, y: int, seed_value: int) -> float:
	var n: int = (x * 374761393 + y * 668265263 + seed_value * 1274126177) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n ^ (n >> 16)) / 2147483647.0


static func _noise(uv: Vector2, cells: Vector2i, seed_value: int) -> float:
	var p: Vector2 = uv * Vector2(cells)
	var x: int = floori(p.x)
	var y: int = floori(p.y)
	var f: Vector2 = p - Vector2(x, y)
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	return lerpf(lerpf(_hash(posmod(x, cells.x), posmod(y, cells.y), seed_value), _hash(posmod(x + 1, cells.x), posmod(y, cells.y), seed_value), f.x), lerpf(_hash(posmod(x, cells.x), posmod(y + 1, cells.y), seed_value), _hash(posmod(x + 1, cells.x), posmod(y + 1, cells.y), seed_value), f.x), f.y)


static func _rock_faces(uv: Vector2) -> float:
	var point: Vector2 = uv * 4.0
	var cell := Vector2i(point.floor())
	var nearest: float = INF
	var second: float = INF
	for y in range(-1, 2):
		for x in range(-1, 2):
			var neighbor := cell + Vector2i(x, y)
			var center := Vector2(neighbor) + Vector2(_hash(posmod(neighbor.x, 4), posmod(neighbor.y, 4), 271), _hash(posmod(neighbor.x, 4), posmod(neighbor.y, 4), 277))
			var distance: float = point.distance_to(center)
			if distance < nearest:
				second = nearest
				nearest = distance
			elif distance < second:
				second = distance
	return clampf((second - nearest) * 2.5, 0, 1)


static func relief(uv: Vector2, layer: int) -> float:
	var broad: float = _noise(uv, Vector2i(8, 8), 19 + layer)
	var grain: float = _noise(uv, Vector2i(64, 64), 47 + layer)
	match layer:
		0, 1: return 0.25 * broad + 0.4 * _noise(uv, Vector2i(48, 16), 81) + 0.35 * grain
		2, 6: return 0.45 * broad + 0.55 * grain
		3: return 0.5 + 0.12 * sin(uv.y * TAU * 16 + broad * 2.0) + 0.18 * (grain - 0.5)
		4:
			var ridge: float = 1.0 - absf(_noise(uv, Vector2i(12, 6), 143) * 2.0 - 1.0)
			return 0.55 * _rock_faces(uv) + 0.25 * broad + 0.15 * ridge + 0.05 * grain
		_: return 0.5 + 0.15 * (broad - 0.5) + 0.08 * (grain - 0.5)


static func base_weights(id: int) -> Color:
	# RGBA = grass, dry grass, soil, sand; ecological identity stays in Biomes.
	match id:
		0, 12: return Color(0, 0, 1, 0)
		1, 2: return Color(0.1, 0.15, 0.65, 0.1)
		3, 4: return Color(0, 0.1, 0.15, 0.75)
		5: return Color(0.1, 0.75, 0.1, 0.05)
		7: return Color(0.3, 0.55, 0.15, 0)
		8, 9, 10, 11, 14: return Color(0.45, 0.05, 0.5, 0)
		13: return Color(0.35, 0.1, 0.55, 0)
		_: return Color(0.8, 0.15, 0.05, 0)


static func ensure_library() -> bool:
	if albedo != null:
		return true
	var diffuse_images: Array[Image] = []
	var normal_images: Array[Image] = []
	for layer in range(NAMES.size()):
		var diffuse := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		var normal := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		var field := PackedFloat32Array()
		field.resize(TILE_SIZE * TILE_SIZE)
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				field[y * TILE_SIZE + x] = relief(Vector2(x, y) / TILE_SIZE, layer)
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				var h: float = field[y * TILE_SIZE + x]
				var contrast: float = 0.22 if layer != 4 else 0.4
				var value: float = 0.5 + (h - 0.5) * contrast
				var tint := Color(1, 1, 1)
				if layer in [2, 6]:
					tint = Color(1.04, 0.97, 0.9)
				var color: Color = Color(value * tint.r, value * tint.g, value * tint.b).linear_to_srgb()
				color.a = h # Explicit micro-height, never biome identity.
				diffuse.set_pixel(x, y, color)
				var dx: float = field[y * TILE_SIZE + posmod(x + 1, TILE_SIZE)] - field[y * TILE_SIZE + posmod(x - 1, TILE_SIZE)]
				var dy: float = field[posmod(y + 1, TILE_SIZE) * TILE_SIZE + x] - field[posmod(y - 1, TILE_SIZE) * TILE_SIZE + x]
				var strength: float = 3.0 if layer == 4 else 1.4
				var n: Vector3 = Vector3(-dx * strength, -dy * strength, 1.0).normalized()
				var roughness: float = [0.92, 0.96, 0.88, 0.98, 0.86, 0.90, 0.76][layer]
				normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, roughness))
		diffuse.generate_mipmaps()
		normal.generate_mipmaps(true)
		diffuse_images.append(diffuse)
		normal_images.append(normal)
	albedo = Texture2DArray.new()
	normals = Texture2DArray.new()
	var diffuse_error: Error = albedo.create_from_images(diffuse_images)
	var normal_error: Error = normals.create_from_images(normal_images)
	if diffuse_error != OK or normal_error != OK:
		push_error("Cannot create terrain texture arrays: %s / %s" % [error_string(diffuse_error), error_string(normal_error)])
		albedo = null
		normals = null
		return false
	var palette := Image.create(Biomes.PALETTE_SIZE.x, Biomes.PALETTE_SIZE.y, false, Image.FORMAT_RGBA8)
	for y in range(palette.get_height()):
		for x in range(palette.get_width()):
			palette.set_pixel(x, y, base_weights(Biomes.classify(-80.0 + x * 0.5, y * 10.0)))
	weights = ImageTexture.create_from_image(Biomes._soften_palette(palette))
	# Both appearance lookups share a broader ecotone; classification remains in Biomes.
	transition_colors = ImageTexture.create_from_image(_ecotone_palette(Biomes.palette_image()))
	transition_weights = ImageTexture.create_from_image(_ecotone_palette(weights.get_image(), true))
	var noise_image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var uv: Vector2 = Vector2(x, y) / TILE_SIZE
			var values := Color(0, 0, 0, 0)
			for channel in range(4):
				values[channel] = _noise(uv, Vector2i(4, 4), 211 + channel * 37) * 0.7 + _noise(uv, Vector2i(8, 8), 229 + channel * 43) * 0.3
			noise_image.set_pixel(x, y, values)
	noise_image.generate_mipmaps()
	transition_noise = ImageTexture.create_from_image(noise_image)
	build_count += 1
	return true


static func _ecotone_palette(source: Image, normalize_weights: bool = false) -> Image:
	# Two box passes form a triangular kernel: +/-4 C and +/-240 mm/year.
	# Sliding sums keep the work linear in palette size, independent of radius.
	var image := source.duplicate() as Image
	image.convert(Image.FORMAT_RGBAF)
	for iteration in range(2):
		for axis in range(2):
			var radius: int = 4 if axis == 0 else 12
			var lines: int = image.get_height() if axis == 0 else image.get_width()
			var length: int = image.get_width() if axis == 0 else image.get_height()
			var target := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBAF)
			for line in range(lines):
				var total := Color(0, 0, 0, 0)
				for tap in range(-radius, radius + 1):
					var index: int = clampi(tap, 0, length - 1)
					total += image.get_pixel(index if axis == 0 else line, line if axis == 0 else index)
				for index in range(length):
					target.set_pixel(index if axis == 0 else line, line if axis == 0 else index, total / float(radius * 2 + 1))
					var leaving: int = clampi(index - radius, 0, length - 1)
					var entering: int = clampi(index + radius + 1, 0, length - 1)
					total -= image.get_pixel(leaving if axis == 0 else line, line if axis == 0 else leaving)
					total += image.get_pixel(entering if axis == 0 else line, line if axis == 0 else entering)
			image = target
	if normalize_weights:
		# Existing RGBA8 palette filtering has rounding loss; publish normalized weights.
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var w: Color = image.get_pixel(x, y)
				w = Color(maxf(w.r, 0), maxf(w.g, 0), maxf(w.b, 0), maxf(w.a, 0))
				image.set_pixel(x, y, w / maxf(w.r + w.g + w.b + w.a, 0.0001))
	image.convert(Image.FORMAT_RGBA8)
	return image


static func bind_library(material: ShaderMaterial, seed_text: String = "42") -> void:
	if not ensure_library():
		material.set_shader_parameter("surface_materials_enabled", false)
		return
	material.set_shader_parameter("surface_albedo", albedo)
	material.set_shader_parameter("surface_normals", normals)
	material.set_shader_parameter("surface_weights", weights)
	material.set_shader_parameter("surface_tile_size", TILE_WORLD_SIZE)
	material.set_shader_parameter("surface_materials_enabled", true)
	material.set_shader_parameter("transition_noise", transition_noise)
	material.set_shader_parameter("transition_colors", transition_colors)
	material.set_shader_parameter("transition_weights", transition_weights)
	var random = Alea.new(seed_text + ":terrain-blending")
	material.set_shader_parameter("blend_seed_offset", Vector2(random.next() * 4096.0, random.next() * 4096.0))


static func habitat_texture(source: Image) -> ImageTexture:
	if source == null:
		return null
	var appearance := source.duplicate() as Image
	appearance.generate_mipmaps()
	return ImageTexture.create_from_image(appearance)


static func regional_field(map_size: Vector2, seed_text: String) -> ImageTexture:
	# Linear RGB multipliers, not a second biome identity/colour map.
	var size: Vector2i = Grid.sample_size_for(map_size, 128)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
	var seed_value: int = posmod(seed_text.hash(), 10000)
	for y in range(size.y):
		for x in range(size.x):
			var uv: Vector2 = Vector2(x, y) / Vector2(size - Vector2i.ONE)
			var broad: float = _noise(uv, Vector2i(5, 5), seed_value) - 0.5
			var local: float = _noise(uv, Vector2i(17, 17), seed_value + 1) - 0.5
			image.set_pixel(x, y, Color(1.0 + broad * 0.12 + local * 0.025, 1.0 + broad * 0.08, 1.0 - broad * 0.08, 1))
	return ImageTexture.create_from_image(image)
