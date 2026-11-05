extends SceneTree
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
const Field = preload("res://scripts/rendering/display_height_field.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Surface = preload("res://scripts/domain/terrain_surface.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var node := MeshInstance3D.new()
	root.add_child(node)
	var renderer := Renderer.new(node)
	var base := PackedFloat32Array([0.3,0.4,0.5,0.3,0.4,0.5,0.3,0.4,0.5])
	var original := base.duplicate()
	var water := Water.new()
	water.mask_size = Vector2i(3,3)
	water.source_hash = "a".repeat(64)
	water.mask_bytes.resize(36)
	water.mask_bytes[4*4+1] = 255
	water.surface_levels.resize(9)
	water.surface_levels.fill(-1)
	water.surface_levels[4] = 0.7
	var surface := Surface.new()
	surface.size = Vector2i(3,3)
	surface.heights = base.duplicate()
	surface.heights[4] = 0.25
	renderer.begin_update()
	renderer.set_heightfield(base,Vector2i(3,3),Vector2(192,192),0,10,2)
	renderer.set_terrain_surface(surface,true)
	renderer.set_water_layer(water,true)
	renderer.end_update()
	check(renderer.display_builds == 1,"One batch builds only its final surface/water combination.")
	check(renderer.display_texture.get_image().get_format() == Image.FORMAT_RF and absf(renderer.display_heights[4]-7.0) < 0.00001,"Full-resolution R32F display field contains world-space water surface.")
	check(base == original and surface.heights[4] == 0.25 and is_equal_approx(water.surface_levels[4],0.7),"Display preparation preserves all canonical inputs.")
	check(absf(renderer.visible_height(Vector2(0.5,0.5))) < 0.00001,"Flat overview remains undisplaced.")
	renderer.set_relief(1)
	check(absf(renderer.visible_height(Vector2(0.5,0.5))-7.0) < 0.00001,"CPU picking field reads the same mesh vertex as the displayed water level.")
	renderer.set_water_layer(water,false)
	check(absf(renderer.display_heights[4]-2.5) < 0.00001,"Hiding water reveals the conditioned bed.")
	var builds := renderer.display_builds
	renderer.set_water_layer(water,true)
	check(renderer.display_builds == builds and renderer.display_cache_hits == 1,"Water visibility reuses the two-entry display cache.")
	for i in range(5):
		renderer.set_relief(float(i)/4)
		renderer.set_shaded_relief(i%2 == 0)
	check(renderer.display_builds == builds,"Zoom and shading do not rebake heights.")
	water.surface_levels[4] = 0.8
	water._hydraulic_hash = ""
	renderer.set_water_layer(water,true)
	check(absf(renderer.display_heights[4]-8) < 0.00001,"Changing hydraulic content on the same owner invalidates display heights.")
	# Clamping after interpolation preserves the pre-cache coastline geometry.
	var shore := Field.new()
	shore.size = Vector2i(4,3)
	shore.extent = Vector2(192,128)
	shore.datum = 0
	shore.base = PackedFloat32Array([0.1,0.21,0.6,0.8,0.1,0.21,0.6,0.8,0.1,0.21,0.6,0.8])
	shore.build()
	check(absf(shore.mesh_heights[shore.mesh_size.x+1]-0.2) < 0.00001,"Sea clamp remains after interpolation so shore geometry does not rise.")
	# A large update runs in the worker. Replacing its source must discard it.
	var large := PackedFloat32Array()
	large.resize(2050*2050)
	large.fill(4.8)
	var started := Time.get_ticks_usec()
	renderer.begin_update()
	renderer.set_heightfield(large,Vector2i(2050,2050),Vector2(1024,1024),0,12,2)
	renderer.end_update(true)
	var submit_usec := Time.get_ticks_usec()-started
	var job_base: PackedFloat32Array = renderer._display_job.base
	var snapshot_height: float = job_base[0]
	renderer.normalized_heights[0] = 0.9
	check(job_base[0] == snapshot_height,"The running worker is isolated from producer array mutations.")
	renderer.normalized_heights[0] = snapshot_height
	check(renderer.display_pending() and not node.visible,"Large updates return with a pending worker and hide stale geometry.")
	var ticks := 0
	while renderer.display_pending():
		await process_frame
		ticks += 1
		renderer.poll_display()
	check(ticks > 0 and renderer.display_texture.get_size() == Vector2(2050,2050),"UI frames continue while the full-resolution display field is prepared.")
	check(absf(renderer.display_heights[0]-25.6) < 0.0001,"2050 display uses elevation and horizontal world scale.")
	print("2050 display: submit %.2f ms, worker %.2f ms, upload %.2f ms, %d processing frames" % [submit_usec/1000.0,renderer.display_prepare_usec/1000.0,renderer.display_upload_usec/1000.0,ticks])
	var alternate := Surface.new()
	alternate.size = Vector2i(2050,2050)
	alternate.heights = renderer.normalized_heights.duplicate()
	alternate.heights.fill(0.6)
	renderer.begin_update()
	renderer.set_terrain_surface(alternate,true)
	renderer.end_update(true)
	var pending_task := renderer._display_task
	renderer.begin_update()
	renderer.set_terrain_surface(null,false)
	renderer.end_update(true)
	check(not renderer.display_pending() and node.visible,"Returning to a cached variant publishes immediately while another job runs.")
	renderer.begin_update()
	renderer.set_terrain_surface(alternate,true)
	renderer.end_update(true)
	check(renderer.display_pending() and not node.visible and renderer._display_task == pending_task,"Returning to an in-flight variant hides stale geometry and reuses its worker.")
	while renderer.display_pending():
		await process_frame
		renderer.poll_display()
	check(absf(renderer.display_heights[0]-38.4) < 0.0001,"The retained worker publishes the requested surface variant.")
	renderer.begin_update()
	renderer.set_heightfield(large,Vector2i(2050,2050),Vector2(1024,1024),0,15,2)
	renderer.end_update(true)
	var newest := large.duplicate()
	newest.fill(6.4)
	renderer.begin_update()
	renderer.set_heightfield(newest,Vector2i(2050,2050),Vector2(1024,1024),0,12,2)
	renderer.end_update(true)
	while renderer.display_pending():
		await process_frame
		renderer.poll_display()
	check(absf(renderer.display_heights[0]-6.4*1024/192) < 0.0001,"Coalesced large replacements publish the newest source only.")
	renderer.begin_update()
	renderer.set_heightfield(large,Vector2i(2050,2050),Vector2(1024,1024),0,15,2)
	renderer.end_update(true)
	renderer.begin_update()
	renderer.set_heightfield(base,Vector2i(3,3),Vector2(192,192),0,10,2)
	renderer.end_update(true)
	check(not renderer.display_pending() and renderer.display_heights.size() == 9,"A new small document replaces an obsolete pending large update immediately.")
	while renderer._display_task >= 0:
		await process_frame
		renderer.poll_display()
	check(renderer.display_heights.size() == 9,"A completed obsolete worker cannot overwrite the replacement document.")
	node.free()
	print("Display height cache: %d failures" % failures)
	quit(1 if failures else 0)
