extends SceneTree
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Surface = preload("res://scripts/domain/terrain_surface.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	world.get_node("Terrain").resolution = 255
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	for preset in Recipe.PRESETS:
		terrain.terrain_template = preset
		terrain.regenerate()
		var water := Water.new()
		var choices: Dictionary = Water.DEFAULTS.duplicate()
		choices.routing_resolution = 257
		var error: String = water.generate(terrain.map_renderer.normalized_heights, terrain.sample_size(), terrain.water_source_hash, choices)
		if error.is_empty():
			error = Water.decode(water.snapshot()).error
		if error.is_empty():
			var surface := Surface.new()
			error = surface.build(terrain.map_renderer.normalized_heights, terrain.sample_size(), terrain.water_source_hash, water)
			if error.is_empty():
				error = surface.validate_water(water)
		if not error.is_empty():
			failures += 1
			push_error(preset + ": " + error)
		print("Terrain surface template %s: %s" % [preset, "PASS" if error.is_empty() else "FAIL"])
		await process_frame
	world.queue_free()
	await process_frame
	print("Terrain surface templates: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
