extends SceneTree
## Production pipeline checks for dimensions, resolution, and legacy documents.

const Document = preload("res://scripts/storage/terrain_document.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	editor._controls["map_size.x"].value = 192
	editor._controls["map_size.y"].value = 96
	editor.apply_settings()
	_check(terrain.map_size == Vector2(192, 96), "Runtime width and height must apply independently.")
	# Exercise the retained domain/export resolution separately from automatic UI policy.
	terrain.resolution = 512
	terrain.regenerate()
	_check(terrain.sample_size() == Vector2i(513, 257), "Rectangular maps must retain equal sample spacing on both axes.")
	var arrays: Array = terrain.get_node("Surface").mesh.surface_get_arrays(0)
	_check(arrays[Mesh.ARRAY_INDEX].size() == 512 * 256 * 6, "Mesh topology must match rectangular dimensions.")
	var coarse: PackedFloat32Array = terrain.height_samples.duplicate()
	terrain.resolution = 1024
	terrain.regenerate()
	_check(terrain.sample_size() == Vector2i(1025, 513), "Highest mesh resolution must preserve map proportions.")
	for y in range(257):
		for x in range(513):
			if coarse[y * 513 + x] != terrain.height_samples[y * 2 * 1025 + x * 2]:
				_check(false, "Mesh resolution must refine the same terrain without rerolling its geography.")
				break
	print("1024 x 512 cells: %.3f s generation" % (terrain.generation_ms / 1000.0))
	_check(terrain.heightmap_image().get_size() == Vector2i(1025, 513), "Exported heightmaps must preserve rectangular sampling dimensions.")
	terrain.map_size = Vector2(192, 192)
	terrain.regenerate()
	_check(terrain.height_samples.size() == 1025 * 1025, "Maximum square map must produce all requested samples.")
	print("1024 x 1024 cells: %.3f s generation" % (terrain.generation_ms / 1000.0))
	var source := Image.create(2, 2, false, Image.FORMAT_RF)
	source.fill(Color(0.47, 0.47, 0.47))
	terrain.heightmap_texture = ImageTexture.create_from_image(source)
	terrain.regenerate()
	var original: PackedFloat32Array = terrain.height_samples.duplicate()
	var path: String = "res://.godot/quality-roundtrip.terrain.json"
	_check(Document.save_file(path, terrain).is_empty(), "Maximum-resolution terrain with embedded image input must save within the document limit.")
	var loaded: Dictionary = Document.load_file(path)
	_check(loaded.ok, "Maximum-resolution terrain document must load.")
	if loaded.ok:
		_check(Document.apply(terrain, loaded.document).is_empty() and terrain.height_samples == original, "High-resolution embedded images and final samples must round-trip exactly.")
		print("Maximum-resolution save with embedded image: %.2f MiB" % (FileAccess.get_file_as_bytes(path).size() / 1048576.0))
	DirAccess.remove_absolute(path)
	terrain.heightmap_texture = null
	terrain.resolution = 16
	terrain.map_size = Vector2(192, 96)
	terrain.regenerate()
	var legacy: Dictionary = Document.capture(terrain)
	legacy.version = 1
	legacy.generator_version = 1
	legacy.erase("sample_size")
	legacy.erase("graph")
	legacy.settings.erase("template_resolution")
	legacy.heights = Array(PackedFloat32Array())
	for i in range(17 * 17):
		legacy.heights.append(float(i % 17) * 0.5)
	_check(Document.apply(terrain, legacy).is_empty(), "Version 1 files must remain loadable.")
	_check(terrain.sample_size() == Vector2i(17, 17) and terrain.height_samples == PackedFloat32Array(legacy.heights), "Legacy square samples must be preserved even on rectangular maps.")
	_check(Document.validate(Document.capture(terrain)).is_empty(), "Loaded legacy terrain must be saveable in the current format without losing its layout.")
	var bad: Dictionary = Document.capture(terrain)
	bad.sample_size[0] = 16.5
	var before: PackedFloat32Array = terrain.height_samples.duplicate()
	_check(not Document.apply(terrain, bad).is_empty() and terrain.height_samples == before, "Fractional sample dimensions must be rejected before mutation.")
	terrain.resolution = 16
	terrain.regenerate()
	_check(terrain.sample_size() == Vector2i(17, 9), "Editing a legacy map must regenerate with the current aspect-aware layout.")
	world.queue_free()
	await process_frame
	print("Terrain quality checks: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)
