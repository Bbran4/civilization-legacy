extends SceneTree
const Relief = preload("res://scripts/rendering/terrain_relief.gd")
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _capture(name_text: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/mountains-" + name_text + ".png")
func _run() -> void:
	var relief = Relief.new(42)
	var repeat = Relief.new(42)
	var other = Relief.new(43)
	var changes: float = 0
	for x in range(100):
		var point := Vector2(x * 1.7, 21.3)
		_check(relief.offset(point, 0.4) == 0, "Lowlands and shores must not receive mountain displacement.")
		_check(relief.offset(point, 0.8) == repeat.offset(point, 0.8), "Ridge generation must repeat for a saved seed.")
		changes += absf(relief.offset(point, 0.8) - other.offset(point, 0.8))
	_check(changes > 0.1, "Different seeds must create different mountain spines.")
	var world = load("res://scenes/main.tscn").instantiate()
	var terrain = world.get_node("Terrain")
	terrain.tree_population = 0
	terrain.micro_detail_strength = 0.0
	root.add_child(world)
	await process_frame
	terrain.map_size = Vector2(256, 192)
	terrain.terrain_template = "High Island"
	terrain.island_enabled = false
	terrain.regenerate()
	world.get_node("Interface/Editor")._sync_from_terrain()
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var ids: PackedByteArray = terrain.biomes.ids.duplicate()
	var flow: PackedFloat64Array = terrain.hydrology.flow.duplicate()
	var field: PackedFloat32Array = terrain.detail.field_heights.duplicate()
	var base_grid: PackedFloat32Array = terrain.graph.rasterize(terrain.detail.field_size, terrain.surface_smoothing)
	var changed_highland: int = 0
	for index in range(field.size()):
		var base: float = (terrain.height_offset + (base_grid[index] - 0.2) * terrain.elevation) * terrain.relief_scale()
		if base_grid[index] <= 0.46:
			_check(absf(field[index] - base) <= terrain.micro_detail_strength + 0.00001, "Lowlands may retain existing micro detail but must not gain mountain displacement.")
		elif absf(field[index] - base) > 0.1:
			changed_highland += 1
	_check(changed_highland > 100, "The real terrain mesh must gain highland relief, not only a rock-colour change.")
	var normal_id: int = terrain.detail.macro_normal_texture.get_instance_id()
	var peak: int = 0
	for index in range(field.size()):
		if field[index] > field[peak]:
			peak = index
	var point := Vector2(peak % terrain.detail.field_size.x, peak / terrain.detail.field_size.x) / Vector2(terrain.detail.field_size - Vector2i.ONE)
	var rig = world.get_node("CameraRig")
	if DisplayServer.get_name() != "headless":
		rig._reset_view()
		await _capture("overview")
		rig.position.x = (point.x - 0.5) * terrain.map_size.x
		rig.position.z = (point.y - 0.5) * terrain.map_size.y
		rig.position.y = field[peak] * 0.7
		rig._pitch = 40
		rig._zoom = rig._fit_size / 65.0
		rig._apply_zoom()
		terrain.detail._process(1)
		await _capture("range")
		rig._zoom = rig._fit_size / 30.0
		rig._apply_zoom()
		terrain.detail._process(1)
		await _capture("close")
		var warm: Dictionary = terrain.climate_settings.duplicate()
		warm.temperature_bias = 20
		terrain.apply_climate(warm)
		await _capture("warm-rock")
		terrain.hydrology_view.visible = false
		await _capture("rock-without-water")
		terrain.hydrology_view.visible = true
		ids = terrain.biomes.ids.duplicate()
		flow = terrain.hydrology.flow.duplicate()
		terrain.set_climate_view(5)
		await _capture("biome-data")
	for zoom in [1, 5, 20]:
		rig._zoom = zoom
		rig._apply_zoom()
		terrain.detail._process(1)
		_check(terrain.height_samples == heights and terrain.biomes.ids == ids and terrain.hydrology.flow == flow, "Mountain presentation and zoom must preserve source geography and ecological data.")
		_check(terrain.detail.field_heights == field and terrain.detail.macro_normal_texture.get_instance_id() == normal_id, "Zoom must keep the mountain field and normals fixed.")
	print("Mountain relief build: ", terrain.detail.field_size, "; ", terrain.detail.build_ms, " ms")
	world.queue_free()
	await process_frame
	print("Mountain terrain checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
