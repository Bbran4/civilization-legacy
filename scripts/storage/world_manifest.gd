extends RefCounted
## A sidecar references an existing terrain document; it never rewrites terrain data.
const Layer = preload("res://scripts/domain/map_layer.gd")
const VERSION = 1

static func default_layers() -> Array:
	return [Layer.new("heightmap", "Heightmap"), Layer.new("rivers", "Rivers / lakes", ["heightmap", "climate"]), Layer.new("climate", "Climate", ["heightmap"]), Layer.new("ground", "Ground paint", ["heightmap"]), Layer.new("trees", "Trees", ["heightmap", "climate", "rivers"])]

static func capture(layers: Array, terrain_path: String, selected: String) -> Dictionary:
	var entries: Array = []
	for layer in layers:
		entries.append(layer.to_dict())
	return {"format": "civilization-legacy-world", "version": VERSION, "terrain": terrain_path, "selected_layer": selected, "layers": entries}

static func validate(data: Dictionary) -> String:
	if data.get("format") != "civilization-legacy-world" or data.get("version") != VERSION:
		return "Unsupported world manifest."
	if not data.get("terrain") is String or data.terrain.is_empty():
		return "A world must reference a terrain save."
	if not data.get("layers") is Array or data.layers.size() != default_layers().size():
		return "Invalid layer stack."
	var ids: Array = []
	for layer in default_layers():
		ids.append(layer.id)
	for entry in data.layers:
		if not entry is Dictionary or not entry.get("id") in ids or not entry.get("visible") is bool or not entry.get("locked") is bool:
			return "Invalid or duplicate layer state."
		ids.erase(entry.id)
	if not data.get("selected_layer") is String:
		return "Invalid selected layer."
	for layer in default_layers():
		if layer.id == data.selected_layer:
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
	return {"error": error, "document": value}
