extends RefCounted
## Bakes authored material assets; textures own colour, masks own coverage.
const Sources = preload("res://scripts/rendering/terrain_materials.gd")
const Catalog = preload("res://scripts/rendering/terrain_paint_catalog.gd")
const Biomes = preload("res://scripts/domain/terrain_biomes.gd")
const SIZE := 256
static var _cached_key: String = ""
static var _cached: Dictionary = {}
static var build_count: int = 0
static var _patterns: Dictionary = {}
static var _biome_indices: ImageTexture

static func _image(texture: Texture2D, path: String, cache: Dictionary) -> Dictionary:
	if texture != null:
		var source: Image = texture.get_image()
		return {"image": _resized(source), "error": "" if source != null and not source.is_empty() else "Texture has no readable image."}
	if path.is_empty():
		return {"image": null, "error": ""}
	if cache.has(path):
		return cache[path]
	if path.begins_with("res://") and ResourceLoader.exists(path, "Texture2D"):
		var asset := load(path) as Texture2D
		if asset != null:
			var image: Image = _resized(asset.get_image())
			var result := {"image": image, "error": "" if image != null else "Texture has no readable image: " + path}
			cache[path] = result
			return result
	if not FileAccess.file_exists(path):
		return {"image": null, "error": "Texture file is missing: " + path}
	var image := Image.new()
	var error: Error = image.load(path)
	var result := {"image": _resized(image) if error == OK else null, "error": "" if error == OK else "Cannot read texture: " + path}
	cache[path] = result
	return result

static func _resized(source: Image) -> Image:
	if source == null:
		return null
	var image := source.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return image

static func _pattern(kind: int) -> Image:
	if _patterns.has(kind):
		return _patterns[kind]
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in range(SIZE):
		for x in range(SIZE):
			var uv := Vector2(x, y) / SIZE
			var value: float = Sources._noise(uv, Vector2i(3, 3) if kind == 0 else Vector2i(8, 8), 421)
			if kind == 2:
				value = 0.5 + 0.5 * sin(uv.y * TAU * 4 + value * 4)
			image.set_pixel(x, y, Color(value, value, value, 1))
	image.generate_mipmaps()
	_patterns[kind] = image
	return image

static func build(catalog: Resource, force: bool = false) -> Dictionary:
	if catalog == null or catalog.get_script() != Catalog or catalog.rows.size() != Catalog.ROW_COUNT:
		return {"ok": false, "error": "Choose a ground palette with 19 rows."}
	for row in catalog.rows:
		if row == null or row.get_script() != Catalog.BiomeAsset or row.variants.size() != Catalog.SLOTS or row.variants.has(null):
			return {"ok": false, "error": "Every ground row needs three texture assets."}
		for v in row.variants:
			if v.get_script() != Catalog.VariantAsset:
				return {"ok": false, "error": "Use ground texture assets in each palette slot."}
	var snapshot: Dictionary = catalog.snapshot()
	var error: String = Catalog.validate_data(snapshot)
	if not error.is_empty():
		return {"ok": false, "error": error}
	var key: String = JSON.stringify(snapshot)
	for row in snapshot.rows:
		for v in row.variants:
			for role in ["albedo", "normal", "coverage"]:
				var path: String = v[role + "_path"]
				if not path.is_empty():
					key += ":" + path + ":" + str(FileAccess.get_modified_time(path.get_slice("::", 0)))
	if not force and key == _cached_key:
		return _cached
	if not Sources.ensure_library():
		return {"ok": false, "error": "The renderer could not create ground textures."}
	var images: Dictionary = {}
	# Resolve all dependencies before replacing any live material or map state.
	var resolved: Array = []
	for row in catalog.rows:
		for v in row.variants:
			var channels: Dictionary = {}
			for role in ["albedo", "normal", "coverage"]:
				var asset: Texture2D = v.get(role)
				if asset != null and asset.resource_path.is_empty() and v.get(role + "_path").is_empty():
					return {"ok": false, "error": "Save the texture as an asset before assigning it to the palette."}
				var loaded: Dictionary = _image(v.get(role), v.get(role + "_path"), images)
				if not loaded.error.is_empty():
					return {"ok": false, "error": loaded.error}
				channels[role] = _resized(loaded.image)
			resolved.append(channels)
	var colors: Array[Image] = []
	var normals: Array[Image] = []
	var masks: Array[Image] = []
	var options := Image.create(3, 19, false, Image.FORMAT_RGBAF)
	for row_id in range(19):
		for slot in range(3):
			var layer: int = row_id * 3 + slot
			var v: Resource = catalog.rows[row_id].variants[slot]
			var source: Dictionary = resolved[layer]
			var diffuse: Image = source.albedo if source.albedo != null else _resized(Sources.source_albedo[v.starter_texture])
			var normal: Image = source.normal if source.normal != null else _resized(Sources.source_normals[v.starter_texture])
			var pattern: Image = source.coverage if source.coverage != null else _pattern(v.pattern)
			for y in range(SIZE):
				for x in range(SIZE):
					var c: Color = diffuse.get_pixel(x, y)
					if source.albedo == null:
						c = Color(c.r / 0.73535698 * v.base_color.r, c.g / 0.73535698 * v.base_color.g, c.b / 0.73535698 * v.base_color.b, c.a)
					# Custom albedo alpha is not interpreted as transparency or micro-height.
					c.a = 0.5 if source.albedo != null else c.a
					diffuse.set_pixel(x, y, c)
					var n: Color = normal.get_pixel(x, y)
					var tangent := Vector3(n.r, n.g, n.b) * 2.0 - Vector3.ONE
					tangent = tangent.normalized() if tangent.length_squared() > 0.00001 else Vector3(0, 0, 1)
					normal.set_pixel(x, y, Color(tangent.x * 0.5 + 0.5, tangent.y * 0.5 + 0.5, tangent.z * 0.5 + 0.5, v.roughness))
			diffuse.generate_mipmaps()
			normal.generate_mipmaps(true)
			if not pattern.has_mipmaps():
				pattern.generate_mipmaps()
			colors.append(diffuse)
			normals.append(normal)
			masks.append(pattern)
			options.set_pixel(slot, row_id, Color(v.tile_size, deg_to_rad(v.rotation), v.amount, v.patch_size))
	var albedo := Texture2DArray.new()
	var detail := Texture2DArray.new()
	var coverage := Texture2DArray.new()
	if albedo.create_from_images(colors) != OK or detail.create_from_images(normals) != OK or coverage.create_from_images(masks) != OK:
		return {"ok": false, "error": "The renderer could not allocate the ground palette."}
	if _biome_indices == null:
		var indices := Image.create(Biomes.PALETTE_SIZE.x, Biomes.PALETTE_SIZE.y, false, Image.FORMAT_R8)
		for y in range(indices.get_height()):
			for x in range(indices.get_width()):
				indices.set_pixel(x, y, Color(Biomes.classify(-80 + x * 0.5, y * 10.0) / 255.0, 0, 0))
		_biome_indices = ImageTexture.create_from_image(indices)
	_cached = {"ok": true, "error": "", "albedo": albedo, "normals": detail, "coverage": coverage, "options": ImageTexture.create_from_image(options), "biomes": _biome_indices}
	_cached_key = key
	build_count += 1
	return _cached

static func bind(material: ShaderMaterial, data: Dictionary) -> void:
	material.set_shader_parameter("paint_albedo", data.albedo)
	material.set_shader_parameter("paint_normals", data.normals)
	material.set_shader_parameter("paint_coverage", data.coverage)
	material.set_shader_parameter("paint_options", data.options)
	material.set_shader_parameter("paint_biomes", data.biomes)
	material.set_shader_parameter("paint_enabled", true)
