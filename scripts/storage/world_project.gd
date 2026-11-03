extends RefCounted
## Publish a new terrain snapshot before replacing the manifest that references it.
## Prior terrain saves and previous world snapshots are never overwritten.
const Manifest = preload("res://scripts/storage/world_manifest.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")

static func save_file(path: String, terrain: Node, layers: Array, selected: String) -> Dictionary:
	if not path.ends_with(".world.json"):
		return {"error": "World projects must end in .world.json."}
	var directory := path.get_base_dir()
	var stem := path.get_file().trim_suffix(".world.json")
	var snapshot_path: String
	# Never reuse a payload filename: the old manifest and its backup must remain valid.
	while true:
		snapshot_path = directory.path_join("%s-%s-%s.terrain.json" % [stem, Time.get_ticks_usec(), randi()])
		if not FileAccess.file_exists(snapshot_path) and not FileAccess.file_exists(snapshot_path + ".tmp"):
			break
	var data := Manifest.capture(layers, snapshot_path.get_file(), selected)
	var error := Manifest.validate(data)
	if not error.is_empty():
		return {"error": error}
	error = Document.save_file(snapshot_path, terrain)
	if not error.is_empty():
		return {"error": error}
	error = Manifest.save_file(path, data)
	if not error.is_empty():
		# This operation created this unique snapshot; no previous document references it.
		DirAccess.remove_absolute(snapshot_path)
		return {"error": error}
	return {"error": "", "terrain_path": snapshot_path}
