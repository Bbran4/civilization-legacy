extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	await terrain.wait_for_presentation()
	var renderer = terrain.map_renderer
	var before: int = renderer.display_builds
	terrain.resolution = 2049
	var source := PackedFloat32Array()
	source.resize(2050*1025)
	source.fill((0.4-0.2)*terrain.elevation)
	terrain.restore_heightfield(source,Vector2i(2050,1025))
	check(renderer.display_pending() and terrain.ray_surface_hit(Vector3(0,1000,0),Vector3.DOWN) == null,"Picking is gated while replacing a large displayed surface.")
	check(not terrain.forest_view.visible,"Forests do not float over an unpublished surface.")
	await terrain.wait_for_presentation()
	check(renderer.display_builds == before+1,"A source regeneration publishes one final relief build.")
	check(terrain.height_samples == source and renderer.display_heights.size() == source.size(),"Published source-resolution display leaves canonical height samples intact.")
	terrain.set_overview_blend(0)
	var hit: Variant = terrain.ray_surface_hit(Vector3(0,1000,0),Vector3.DOWN)
	check(hit != null and absf(hit.y-terrain.visible_surface_height(Vector2(0.5,0.5))) < 0.0001,"Picking resumes at the displayed mesh surface after publication.")
	var editor = world.get_node("Interface/Editor")
	editor.play_map()
	await process_frame
	check(editor._gameplay_map != null,"A valid maximum-resolution map opens in Play map.")
	if editor._gameplay_map == null:
		print(editor._status.text)
		quit(1)
		return
	var player = editor._gameplay_map.get_node("Terrain")
	await player.wait_for_presentation()
	check(player.height_samples == source and player.map_renderer.display_heights == renderer.display_heights,"Play map reconstructs the identical display field from the saved model.")
	editor._return_from_map()
	await process_frame
	world.free()
	print("Display height integration: %d failures" % failures)
	quit(1 if failures else 0)
