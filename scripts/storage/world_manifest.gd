extends RefCounted
## A sidecar references an existing terrain document; it never rewrites terrain data.
const Layer = preload("res://scripts/domain/map_layer.gd")
const VERSION = 6

static func _legacy_layers() -> Array:
	return [Layer.new("heightmap", "Heightmap"), Layer.new("rivers", "Rivers / lakes", ["heightmap", "climate"]), Layer.new("surface", "Terrain surface", ["heightmap", "rivers"]), Layer.new("provinces", "Provinces", ["surface"]), Layer.new("climate", "Climate", ["heightmap"]), Layer.new("ground", "Ground paint", ["heightmap"]), Layer.new("trees", "Trees", ["heightmap", "climate", "rivers"])]

static func default_layers() -> Array:
	return [Layer.new("heightmap", "Heightmap"), Layer.new("paint", "Ground paint"), Layer.new("rivers", "Rivers / lakes", ["heightmap"]), Layer.new("surface", "Terrain surface", ["heightmap", "rivers"]), Layer.new("provinces", "Provinces", ["surface"]), Layer.new("trees", "Trees", ["heightmap", "rivers", "paint"])]

static func _layers_for_version(version: int) -> Array:
	if version >= 6: return default_layers()
	if version == 5: return default_layers().filter(func(layer): return layer.id != "trees")
	if version == 4: return default_layers().filter(func(layer): return layer.id not in ["paint","trees"])
	return _legacy_layers()

static func capture(layers: Array, terrain_path: String, selected: String) -> Dictionary:
	var entries: Array = []
	for layer in layers:
		entries.append(layer.to_dict())
	return {"format": "civilization-legacy-world", "version": VERSION, "terrain": terrain_path, "selected_layer": selected, "layers": entries}

static func validate(data: Dictionary) -> String:
	if data.get("format") != "civilization-legacy-world" or data.get("version") not in [1, 1.0, 2, 2.0, 3, 3.0, 4, 4.0, 5, 5.0, VERSION, float(VERSION)]:
		return "Unsupported world manifest."
	if not data.get("terrain") is String or data.terrain.is_empty():
		return "A world must reference a terrain save."
	if not data.get("layers") is Array or data.layers.size() != (6 if data.version >= 6 else (5 if data.version == 5 else (4 if data.version == 4 else (5 if data.version == 1 else (6 if data.version == 2 else 7))))):
		return "Invalid layer stack."
	var ids: Array = []
	for layer in _layers_for_version(int(data.version)):
		if (data.version != 1 or layer.id != "surface") and (data.version >= 3 or layer.id != "provinces"):
			ids.append(layer.id)
	for entry in data.layers:
		if not entry is Dictionary or not entry.get("id") in ids or not entry.get("visible") is bool or not entry.get("locked") is bool:
			return "Invalid or duplicate layer state."
		ids.erase(entry.id)
	if not data.get("selected_layer") is String:
		return "Invalid selected layer."
	for layer in _layers_for_version(int(data.version)):
		if layer.id == data.selected_layer and (data.version != 1 or layer.id != "surface") and (data.version >= 3 or layer.id != "provinces"):
			return ""
	return "Unknown selected layer."

static func save_file(path: String, data: Dictionary) -> String:
	var error := validate(data)
	if not error.is_empty():
		return error
	# Require a distinct suffix, so a terrain save cannot be overwritten accidentally.
	if not path.ends_with(".world.json"):
		return "World manifests must end in .world.json."
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(path, path + ".bak") != OK:
			return "Could not back up the world manifest."
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return "Could not write world manifest."
	file.store_string(JSON.stringify(data, "  "))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(path + ".tmp")
		return "Writing the world manifest failed; the previous save was kept."
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		DirAccess.remove_absolute(path + ".tmp")
		return "Could not replace world manifest."
	return ""

static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Could not read world manifest."}
	if file.get_length() > 1024 * 1024:
		return {"error": "World manifest is too large."}
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary:
		return {"error": "Invalid world JSON."}
	var error := validate(value)
	if error.is_empty() and value.version == 1:
		value.layers.insert(2, Layer.new("surface", "Terrain surface").to_dict())
	if error.is_empty() and value.version < 3:
		value.layers.insert(3, Layer.new("provinces", "Provinces").to_dict())
	if error.is_empty():
		if value.version < 6:
			value.layers = value.layers.filter(func(entry): return entry.id in ["heightmap", "paint", "rivers", "surface", "provinces"])
			value.layers.append(Layer.new("trees","Trees",["heightmap","rivers","paint"]).to_dict())
		if value.version < 5: value.layers.insert(1, Layer.new("paint", "Ground paint").to_dict())
		if value.selected_layer not in ["heightmap", "paint", "rivers", "surface", "provinces", "trees"]: value.selected_layer = "heightmap"
		value.version = VERSION
	return {"error": error, "document": value}
