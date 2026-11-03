extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Paths = preload("res://scripts/rendering/province_border_paths.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
const History = preload("res://scripts/domain/province_edit_history.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var layer := Provinces.new()
	layer.size = Vector2i(129,129)
	layer.source_hash = "a".repeat(64)
	layer.ids.resize(129*129)
	for y in range(129):
		for x in range(129):
			layer.ids[y*129+x] = (1 if y < 64 else 2) if x < 64+int(sin(y*0.09)*7) else 3
	for i in range(3): layer.records.append({"id":i+1,"name":"Province "+str(i+1),"kind":"land"})
	check(layer._index_regions().is_empty(),"Fixture has complete connected provinces.")
	var original := layer.ids.duplicate()
	var red := layer.add_nation("West",Color(0.9,0.06,0.03))
	var blue := layer.add_nation("East",Color(0.03,0.15,0.95))
	layer.assign_nation(1,red)
	layer.assign_nation(2,red)
	layer.assign_nation(3,blue)
	var decoded := Provinces.decode(JSON.parse_string(JSON.stringify(layer.snapshot())))
	check(decoded.error.is_empty() and decoded.layer.nations.size() == 2 and decoded.layer.nation_color(1).is_equal_approx(layer.nation_color(1)) and decoded.layer.records[2].nation_id == blue,"Nation colors and assignments survive JSON.")
	var legacy := layer.snapshot()
	legacy.version = 6
	legacy.erase("nations")
	var old := Provinces.decode(legacy)
	check(old.error.is_empty() and old.layer.nations.is_empty() and old.layer.ids == original,"Legacy saves retain exact IDs without invented nations.")
	var bad := layer.snapshot()
	bad.records[0].nation_id = 99
	check(not Provinces.decode(bad).error.is_empty(),"Invalid nation references are rejected.")
	var paths := Paths.new()
	paths.build(layer.ids,layer.size)
	check(paths.paths.size() == 3 and layer.ids == original,"Shared borders are traced once without changing authoritative pixels.")
	for path in paths.paths:
		for i in range(path.points.size()-1):
			var a: Vector2 = path.points[i]
			var b: Vector2 = path.points[i+1]
			check(a == a.round() and (a.x == b.x or a.y == b.y),"Generated border turns remain on exact raster edges.")
	var tiny := PackedInt32Array([0,0,0,0,1,0,0,0,0])
	var island_paths := Paths.new()
	island_paths.build(tiny,Vector2i(3,3))
	check(island_paths.paths.size() == 1 and island_paths.paths[0].points.size() >= 5,"One-pixel island outlines remain closed after smoothing.")
	var history := History.new()
	var split := history.split(layer,1,PackedVector2Array([Vector2(25,-2),Vector2(25,66)]))
	check(split.error.is_empty() and split.layer.records[split.new_id-1].nation_id == red,"Splits inherit the original nation.")
	var undone := history.undo(split.layer)
	check(undone.error.is_empty() and undone.layer.ids == original and undone.layer.nations == layer.nations,"Border undo preserves nation metadata.")
	var merged := History.new().merge(layer,1,[1,3])
	check(merged.error.is_empty() and merged.layer.records[0].nation_id == red and not merged.layer.records[2].active,"Merging different nations keeps the selected province's nation.")
	var large := PackedInt32Array()
	large.resize(2050*2050)
	for y in range(2050):
		for x in range(2050): large[y*2050+x] = 1 if x < 1025 else 2
	var max_paths := Paths.new()
	max_paths.build(large,Vector2i(2050,2050))
	check(max_paths.paths.size() == 1 and max_paths.paths[0].points.size() == 2,"2050-pixel output traces one continuous shared border.")
	var surface := MeshInstance3D.new()
	root.add_child(surface)
	var renderer := Renderer.new(surface)
	var heights := PackedFloat32Array()
	heights.resize(layer.ids.size())
	for y in range(129):
		for x in range(129): heights[y*129+x] = 0.5+0.1*sin(x*0.12)*cos(y*0.15)
	renderer.set_heightfield(heights,layer.size,Vector2(100,100),0,1,2)
	renderer.material.set_shader_parameter("province_fill",true)
	renderer.set_provinces(layer,true)
	check(renderer.borders.root.get_child_count() == 2,"Renderer groups dashed province lines and solid nation lines.")
	var cached = layer.border_geometry
	renderer.set_provinces(layer,true)
	check(layer.border_geometry == cached,"Unchanged border geometry is cached.")
	renderer.set_provinces(layer,true,true)
	check(not renderer.borders.root.visible and not renderer.material.get_shader_parameter("vector_borders"),"Brush previews use immediate raster feedback without expensive retracing.")
	renderer.set_provinces(layer,true)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1000,800)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 115
		root.add_child(camera)
		camera.position = Vector3(0,100,0)
		camera.rotation_degrees = Vector3(-90,0,0)
		camera.current = true
		for i in range(5): await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var reds := 0
		var blues := 0
		var darks := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var c := image.get_pixel(x,y)
				if c.r > c.g*1.4 and c.r > c.b*1.4: reds += 1
				if c.b > c.r*1.4 and c.b > c.g*1.4: blues += 1
				if c.r < 0.15 and c.g < 0.15 and c.b < 0.15: darks += 1
		check(reds > 200 and blues > 200 and darks > 100,"GPU renders nation-colored province fills and dark borders.")
		var left_red := 0
		var right_blue := 0
		for y in range(10,119,4):
			var x := 64+int(sin(y*0.09)*7)
			var center := camera.unproject_position(Vector3((float(x)/129-0.5)*100,0.06,(float(y)/129-0.5)*100))
			center *= Vector2(image.get_size())/root.get_visible_rect().size
			if center.y < 2 or center.y >= image.get_height()-2: continue
			for offset in range(6,10):
				var left := image.get_pixelv(Vector2i(center+Vector2(-offset,0)))
				var right := image.get_pixelv(Vector2i(center+Vector2(offset,0)))
				if left.r > left.b*1.4: left_red += 1
				if right.b > right.r*1.4: right_blue += 1
		check(left_red > 20 and right_blue > 20,"Province fills retain their nation colors on the correct side.")
		var output := OS.get_environment("BORDER_OUTPUT")
		if not output.is_empty(): image.save_png(output.path_join("smooth-nation-borders.png"))
	surface.queue_free()
	await process_frame
	print("Smooth province borders: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
