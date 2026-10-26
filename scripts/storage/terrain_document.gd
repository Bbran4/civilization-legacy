extends RefCounted
## Versioned terrain-only documents. Parse and validate completely before applying.

const Biomes = preload("res://scripts/domain/terrain_biomes.gd")
const Hydrology = preload("res://scripts/domain/terrain_hydrology.gd")
const Climate = preload("res://scripts/domain/terrain_climate.gd")
const Geography = preload("res://scripts/domain/terrain_geography.gd")
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const VERSION: int = 9
const MAX_BYTES: int = 64 * 1024 * 1024
const NUMBERS: Dictionary = {
	"tree_population": [0, 250000, true],
	"close_detail_resolution": [32, 256, true], "micro_detail_strength": [0, 2],
	"graph_points": [1000, 100000, true], "surface_smoothing": [0, 4, true],
	"resolution": [16, 1024, true], "template_resolution": [32, 256, true], "elevation": [1, 100], "height_offset": [-50, 50],
	"height_contrast": [0.25, 4], "mountain_strength": [0, 1],
	"image_blend": [0, 1], "island_inner_radius": [0.1, 0.95],
	"island_roundness": [1, 8], "sea_level": [-40, 80], "beach_width": [0.1, 10],
	"rock_slope": [0.05, 0.8], "snow_height": [0, 100],
	"feature_scale": [0.5, 1.5], "template_detail": [0, 0.25], "smoothing_passes": [0, 6, true]
}
const BOOLEANS: Array[String] = ["island_enabled", "show_water", "invert_image", "auto_density", "close_detail_enabled"]
const COLORS: Array[String] = ["water_color", "sand_color", "grass_color", "rock_color", "snow_color"]
const NOISE_NUMBERS: Dictionary = {
	"seed": [-2147483648, 2147483647, true], "noise_type": [0, 5, true],
	"frequency": [0.00001, 1], "fractal_type": [0, 3, true], "fractal_octaves": [1, 10, true],
	"fractal_gain": [0, 1], "fractal_lacunarity": [0, 20],
	"fractal_weighted_strength": [0, 1], "fractal_ping_pong_strength": [0, 20],
	"cellular_distance_function": [0, 3, true], "cellular_jitter": [0, 1],
	"cellular_return_type": [0, 6, true], "domain_warp_type": [0, 2, true],
	"domain_warp_amplitude": [0, 1000], "domain_warp_frequency": [0.00001, 1],
	"domain_warp_fractal_type": [0, 2, true], "domain_warp_fractal_octaves": [1, 10, true],
	"domain_warp_fractal_lacunarity": [0, 20], "domain_warp_fractal_gain": [0, 1]
}


static func capture(terrain: Node) -> Dictionary:
	var settings: Dictionary = {}
	for key in NUMBERS:
		settings[key] = terrain.get(key)
	for key in BOOLEANS:
		settings[key] = terrain.get(key)
	for key in COLORS:
		var color: Color = terrain.get(key)
		settings[key] = [color.r, color.g, color.b, color.a]
	settings["map_size"] = [terrain.map_size.x, terrain.map_size.y]
	settings["noise_offset"] = [terrain.noise_offset.x, terrain.noise_offset.y]
	settings["terrain_template"] = terrain.terrain_template
	settings["map_seed"] = terrain.map_seed
	for key in ["land_noise", "mountain_noise"]:
		var noise: FastNoiseLite = terrain.get(key)
		var values: Dictionary = {}
		if noise == null:
			settings[key] = null
			continue
		for property in NOISE_NUMBERS:
			values[property] = noise.get(property)
		values["domain_warp_enabled"] = noise.domain_warp_enabled
		values["offset"] = [noise.offset.x, noise.offset.y, noise.offset.z]
		settings[key] = values
	var source: Dictionary = terrain.source_image_snapshot()
	if source.has("error"):
		return {}
	return {"format": "civilization-legacy-terrain", "version": VERSION,
		"biomes": {"version": Biomes.VERSION}, "hydrology": {"version": Hydrology.VERSION}, "generator_version": terrain.generator_version, "climate": {"version": Climate.VERSION, "settings": terrain.climate_settings.duplicate()}, "settings": settings, "source_image": source,
		"sample_size": [terrain.sample_size().x, terrain.sample_size().y], "graph": terrain.graph_snapshot(),
		"heights": Array(terrain.height_samples), "geography": terrain.geography_snapshot()}


static func validate(document: Variant) -> String:
	if not document is Dictionary:
		return "The file must contain a terrain document object."
	if document.get("format") != "civilization-legacy-terrain" or not _within(document.get("version"), [1, VERSION, true]):
		return "This is not a supported Civilization Legacy terrain file (versions 1–9)."
	if not _within(document.get("generator_version"), [1, 4, true]):
		return "The terrain generator version is unsupported."
	var settings: Variant = document.get("settings")
	if not settings is Dictionary:
		return "Terrain settings are missing."
	if not settings.get("terrain_template") is String or (settings.terrain_template != "Noise" and not Recipe.PRESETS.has(settings.terrain_template) and not Recipe.PRECREATED.has(settings.terrain_template)):
		return "Unknown heightmap template."
	if document.version >= 3 and (not settings.get("map_seed") is String or settings.map_seed.is_empty() or settings.map_seed.length() > 128):
		return "Invalid map seed."
	for key in NUMBERS:
		if document.version < 9 and key == "tree_population":
			continue
		if document.version < 4 and key in ["close_detail_resolution", "micro_detail_strength"]:
			continue
		if document.version < 3 and key in ["graph_points", "surface_smoothing"]:
			continue
		if document.version == 1 and key == "template_resolution":
			continue
		if not _within(settings.get(key), NUMBERS[key]):
			return "Invalid terrain setting: " + key
	for key in BOOLEANS:
		if document.version < 4 and key in ["auto_density", "close_detail_enabled"]:
			continue
		if not settings.get(key) is bool:
			return "Invalid terrain switch: " + key
	for key in COLORS:
		if not _vector(settings.get(key), 4, 0.0, 1.0):
			return "Invalid terrain color: " + key
	if not _vector(settings.get("map_size"), 2, 8.0, 8192.0) or not _vector(settings.get("noise_offset"), 2, -1000000.0, 1000000.0):
		return "Map size or noise offset is invalid."
	for key in ["land_noise", "mountain_noise"]:
		if not settings.has(key):
			return "Missing noise settings: " + key
		var values: Variant = settings[key]
		if values == null:
			continue
		if not values is Dictionary:
			return "Invalid noise settings: " + key
		for property in NOISE_NUMBERS:
			if not _within(values.get(property), NOISE_NUMBERS[property]):
				return "Invalid noise value: " + key + "." + property
		if not values.get("domain_warp_enabled") is bool or not _vector(values.get("offset"), 3, -1000000.0, 1000000.0):
			return "Invalid noise warp or offset."
	if document.version >= 2 and not _vector(document.get("sample_size"), 2, 3, int(settings.resolution) + 1):
		return "Invalid sample dimensions."
	var size: Vector2i = _sample_size(document)
	if document.version >= 2 and (float(document.sample_size[0]) != size.x or float(document.sample_size[1]) != size.y or maxi(size.x, size.y) != int(settings.resolution) + 1):
		return "Sample dimensions must be whole numbers matching the mesh resolution."
	if not _samples(document.get("heights"), size.x * size.y, -70.0, 150.0):
		return "Terrain samples do not match the saved resolution or height bounds."
	var source: Variant = document.get("source_image")
	if not source is Dictionary or not source.get("path") is String or not source.get("red_samples") is Array:
		return "Invalid saved source image."
	if not source.red_samples.is_empty():
		if not _samples(source.red_samples, size.x * size.y, 0.0, 1.0) or not _vector(source.get("original_size"), 2, 1.0, 65536.0):
			return "Invalid saved heightmap image samples."
	if document.version >= 3:
		var graph_error: String = _validate_graph(document.get("graph"), int(document.generator_version))
		if not graph_error.is_empty():
			return graph_error
	if document.version >= 5:
		var geography_error: String = Geography.validate_cache(document.get("geography"), document.graph, Vector2(settings.map_size[0], settings.map_size[1]), int(settings.surface_smoothing))
		if not geography_error.is_empty():
			return geography_error
	if document.version >= 6:
		var climate: Variant = document.get("climate")
		if not climate is Dictionary or not _within(climate.get("version"), [Climate.VERSION, Climate.VERSION, true]):
			return "Unsupported climate data."
		var climate_error: String = Climate.validate(climate.get("settings"))
		if not climate_error.is_empty():
			return climate_error
	if document.version >= 8:
		var biomes: Variant = document.get("biomes")
		if not biomes is Dictionary or not _within(biomes.get("version"), [Biomes.VERSION, Biomes.VERSION, true]):
			return "Unsupported biome data."
	if document.version >= 7:
		var hydrology: Variant = document.get("hydrology")
		if not hydrology is Dictionary or not _within(hydrology.get("version"), [Hydrology.VERSION, Hydrology.VERSION, true]):
			return "Unsupported hydrology data."
	return ""


static func apply(terrain: Node, document: Dictionary) -> String:
	var error: String = validate(document)
	if not error.is_empty():
		return error
	var settings: Dictionary = document.settings
	var size: Vector2i = _sample_size(document)
	for key in NUMBERS:
		var defaults: Dictionary = {"tree_population": 20000, "graph_points": 10000, "surface_smoothing": 1, "template_resolution": 192, "close_detail_resolution": 128, "micro_detail_strength": 0.15}
		var legacy: bool = (document.version < 9 and key == "tree_population") or (document.version < 3 and key in ["graph_points", "surface_smoothing"]) or (document.version < 4 and key in ["close_detail_resolution", "micro_detail_strength"])
		var value: Variant = defaults[key] if legacy else settings.get(key, defaults.get(key, 0))
		terrain.set(key, int(value) if NUMBERS[key].size() > 2 else float(value))
	for key in BOOLEANS:
		terrain.set(key, (key == "close_detail_enabled") if document.version < 4 and key in ["auto_density", "close_detail_enabled"] else settings[key])
	for key in COLORS:
		var values: Array = settings[key]
		terrain.set(key, Color(values[0], values[1], values[2], values[3]))
	terrain.map_size = Vector2(settings.map_size[0], settings.map_size[1])
	terrain.noise_offset = Vector2(settings.noise_offset[0], settings.noise_offset[1])
	terrain.terrain_template = settings.terrain_template
	terrain.map_seed = settings.map_seed if document.version >= 3 else (str(int(settings.land_noise.seed)) if settings.land_noise != null else "42")
	for key in ["land_noise", "mountain_noise"]:
		var values: Variant = settings[key]
		if values == null:
			terrain.set(key, null)
			continue
		var noise := FastNoiseLite.new()
		for property in NOISE_NUMBERS:
			noise.set(property, int(values[property]) if NOISE_NUMBERS[property].size() > 2 else float(values[property]))
		noise.domain_warp_enabled = values.domain_warp_enabled
		noise.offset = Vector3(values.offset[0], values.offset[1], values.offset[2])
		terrain.set(key, noise)
	terrain.heightmap_texture = null
	terrain.source_heightmap_path = document.source_image.path
	terrain.source_heightmap_size = Vector2i.ZERO
	if not document.source_image.red_samples.is_empty():
		terrain.source_heightmap_size = Vector2i(document.source_image.original_size[0], document.source_image.original_size[1])
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RF)
		for y in range(size.y):
			for x in range(size.x):
				var height: float = document.source_image.red_samples[y * size.x + x]
				image.set_pixel(x, y, Color(height, height, height, 1.0))
		terrain.heightmap_texture = ImageTexture.create_from_image(image)
	terrain.climate_settings = document.climate.settings.duplicate() if document.version >= 6 else Climate.DEFAULTS.duplicate()
	terrain.restore_graph(document.graph if document.version >= 3 else {})
	terrain.restore_heightfield(PackedFloat32Array(document.heights), size, int(document.generator_version))
	return ""


static func save_file(path: String, terrain: Node) -> String:
	var document: Dictionary = capture(terrain)
	var error: String = validate(document)
	if not error.is_empty():
		return "Cannot save: " + error
	var encoded: String = JSON.stringify(document, "", true, true)
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return "Terrain file exceeds the 64 MiB document limit."
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not write the selected location (error %d)." % FileAccess.get_open_error()
	file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return "Writing the terrain file failed; the previous save was kept."
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(path, path + ".bak") != OK:
			DirAccess.remove_absolute(temporary)
			return "Could not back up the previous save; it was not replaced."
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return "Could not replace the save file; the previous file was kept."
	return ""


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Could not open the selected terrain file."}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false, "error": "The terrain file exceeds 64 MiB."}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return {"ok": false, "error": "Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	var error: String = validate(parser.data)
	if not error.is_empty():
		return {"ok": false, "error": error}
	return {"ok": true, "document": parser.data}


static func _within(value: Variant, limits: Array) -> bool:
	if not (value is float or value is int):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= limits[0] and number <= limits[1] and (limits.size() < 3 or number == floor(number))


static func _vector(value: Variant, size: int, minimum: float, maximum: float) -> bool:
	return value is Array and _samples(value, size, minimum, maximum)


static func _samples(value: Variant, count: int, minimum: float, maximum: float) -> bool:
	if not value is Array or value.size() != count:
		return false
	for sample in value:
		if not _within(sample, [minimum, maximum]):
			return false
	return true


static func _sample_size(document: Dictionary) -> Vector2i:
	if document.version == 1:
		return Vector2i.ONE * (int(document.settings.resolution) + 1)
	return Vector2i(int(document.sample_size[0]), int(document.sample_size[1]))


static func _validate_graph(data: Variant, generator_version: int) -> String:
	if not data is Dictionary:
		return "Missing graph data."
	if data.is_empty():
		return "" if generator_version < 3 else "Missing Voronoi cell data."
	if not _within(data.get("columns"), [1, 200000, true]) or not _within(data.get("rows"), [1, 200000, true]) or not _within(data.get("spacing"), [0.01, 8192.0]):
		return "Invalid graph lattice dimensions."
	var count: int = int(data.columns) * int(data.rows)
	if count > 200000 or not _samples(data.get("heights"), count, 0.0, 100.0):
		return "Invalid cell-height data."
	for value in data.heights:
		if float(value) != floorf(float(value)):
			return "Cell heights must be integers."
	if not data.get("points") is Array or data.points.size() < count or data.points.size() > count + 20000:
		return "Invalid graph points."
	for point in data.points:
		if not _vector(point, 2, -16384.0, 24576.0):
			return "Invalid graph coordinates."
	var indices: Variant = data.get("triangles")
	if not indices is Array or indices.size() < 3 or indices.size() % 3 != 0 or indices.size() > data.points.size() * 6:
		return "Invalid graph triangles."
	for index in indices:
		if not _within(index, [0, data.points.size() - 1, true]):
			return "Graph triangle index is outside the saved points."
	for i in range(0, indices.size(), 3):
		if indices[i] == indices[i + 1] or indices[i] == indices[i + 2] or indices[i + 1] == indices[i + 2]:
			return "Graph contains a collapsed triangle."
	return ""
