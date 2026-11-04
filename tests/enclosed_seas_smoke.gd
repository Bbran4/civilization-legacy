extends SceneTree
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Surface = preload("res://scripts/domain/terrain_surface.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
const Texturing = preload("res://scripts/domain/terrain_texturing.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: _run.call_deferred()
func capture() -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func sample(image: Image,camera: Camera3D,uv: Vector2) -> Color:
	var point := (uv-Vector2.ONE*0.5)*Vector2(96,72)
	var pixel := camera.unproject_position(Vector3(point.x,0,point.y))*Vector2(image.get_size())/root.get_visible_rect().size
	return image.get_pixelv(Vector2i(pixel))
func _run() -> void:
	var size := Vector2i(129,97)
	var base := PackedFloat32Array()
	base.resize(size.x*size.y)
	base.fill(0.55)
	for y in range(24,73):
		for x in range(25,104): base[y*size.x+x] = 0.08+float(x-25)/79*0.1
	for y in range(10,14):
		for x in range(10,14): base[y*size.x+x] = 0.1
	var sea := 48*size.x+64
	var lake := 11*size.x+11
	var water := Water.new()
	check(water.generate(base,size,"a".repeat(64),Water.DEFAULTS).is_empty(),"Generate actual water for an enclosed-sea map")
	check(water.ocean[sea] != 0 and water.mask_bytes[sea*4+1] == 0,"Enclosed regional sea stays at sea level and is not painted as a lake")
	check(water.ocean[lake] == 0 and water.mask_bytes[lake*4+1] > 0,"Small inland depression still generates an ordinary lake")
	var surface := Surface.new()
	surface.size = size
	surface.heights = base.duplicate()
	surface.source_hash = water.source_hash
	var layer := Provinces.new()
	check(layer.generate(base,surface,water,8).is_empty(),"Generate land around the enclosed sea")
	var land_ids := layer.ids.duplicate()
	var legacy_data := layer.snapshot()
	legacy_data.version = 8
	legacy_data.erase("enclosed_seas")
	var legacy := Provinces.decode(legacy_data)
	var old_water := Water.new()
	old_water.mask_size = size
	old_water.mask_bytes = water.mask_bytes.duplicate()
	for y in range(24,73):
		for x in range(25,104): old_water.mask_bytes[(y*size.x+x)*4+1] = 255
	check(legacy.error.is_empty() and not legacy.layer.enclosed_seas and legacy.layer.validate_coverage(base,0.2,old_water).is_empty(),"Legacy lake classification loads without rewriting province IDs")
	check(legacy.layer.generate_oceans(base,old_water,8,"coastal_band",64).is_empty() and legacy.layer.enclosed_seas,"Ocean regeneration upgrades old lake-masked seas")
	check(legacy.layer.validate_coverage(base,0.2,old_water).is_empty(),"Upgraded coverage validates with the original saved water mask")
	check(layer.generate_oceans(base,water,8,"coastal_band",64).is_empty(),"Coastal ocean provinces generate inside enclosed seas")
	var shore := 48*size.x+28
	check(layer.ids[shore] > 0 and layer.records[layer.ids[shore]-1].kind == "ocean" and layer.ids[sea] == 0,"Coastal reach assigns shore water and leaves deep sea unassigned")
	var unchanged := true
	for i in range(base.size()):
		if land_ids[i] > 0 and layer.ids[i] != land_ids[i]: unchanged = false
	check(unchanged and layer.ids[lake] == 0 and layer.validate_coverage(base,0.2,water).is_empty(),"Ocean generation preserves land IDs and small generated lakes")
	var restored := Provinces.decode(JSON.parse_string(JSON.stringify(layer.snapshot())))
	check(restored.error.is_empty() and restored.layer.enclosed_seas and restored.layer.ids == layer.ids and restored.layer.validate_coverage(base,0.2,water).is_empty(),"Enclosed-sea policy and provinces round-trip through JSON")
	var full: RefCounted = layer.editable_copy()
	check(full.generate_oceans(base,water,8,"open",64).is_empty() and full.ids[sea] > 0,"Full-ocean mode also partitions the enclosed sea interior")
	if DisplayServer.get_name() != "headless":
		var mesh := MeshInstance3D.new()
		root.add_child(mesh)
		var renderer := Renderer.new(mesh)
		var heights := base.duplicate()
		for i in range(heights.size()): heights[i] *= 12
		renderer.set_heightfield(heights,size,Vector2(96,72),0,12,2)
		renderer.set_texturing(Texturing.DEFAULTS,"sea-fixture",true)
		renderer.set_water_layer(water,true)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.position = Vector3(0,100,0)
		camera.rotation_degrees = Vector3(-90,0,0)
		camera.size = 90
		root.add_child(camera)
		var original := await capture()
		var interior := -1
		for y in range(28,68):
			for x in range(29,99):
				var i := y*size.x+x
				if base[i] > 0.2 or layer.ids[i] == 0: continue
				var safe := true
				for dy in range(-3,4):
					for dx in range(-3,4):
						if layer.ids[i+dy*size.x+dx] != layer.ids[i]: safe = false
				if safe: interior = i; break
			if interior >= 0: break
		check(interior >= 0,"Find an assigned sea sample away from border ink")
		if interior >= 0:
			var assigned_uv := (Vector2(interior%size.x,interior/size.x)+Vector2.ONE*0.5)/Vector2(size)
			renderer.set_provinces(layer,true)
			var filled := await capture()
			check(sample(filled,camera,Vector2(0.5,0.5)).is_equal_approx(sample(original,camera,Vector2(0.5,0.5))),"Unassigned ocean keeps its original color in filled mode")
			check(not sample(filled,camera,assigned_uv).is_equal_approx(sample(original,camera,assigned_uv)),"Filled mode colors only assigned ocean province interiors")
			renderer.material.set_shader_parameter("province_fill",false)
			var borders := await capture()
			check(sample(borders,camera,assigned_uv).is_equal_approx(sample(original,camera,assigned_uv)) and sample(borders,camera,Vector2(0.5,0.5)).is_equal_approx(sample(original,camera,Vector2(0.5,0.5))),"Borders-only mode preserves both assigned and unassigned water colors")
			DirAccess.make_dir_recursive_absolute("res://.test-runtime")
			borders.save_png("res://.test-runtime/enclosed-sea-borders.png")
			filled.save_png("res://.test-runtime/enclosed-sea-filled.png")
		mesh.free()
		camera.free()
	# Exercise both shipped Mediterranean inputs, beyond the controlled basin.
	for preset in ["Mediterranean","Mediterranean heightmap"]:
		var world = load("res://scenes/main.tscn").instantiate()
		var terrain = world.get_node("Terrain")
		terrain.resolution = 128
		terrain.graph_points = 1000
		terrain.map_size = Vector2(192,144)
		terrain.terrain_template = preset
		root.add_child(world)
		await process_frame
		var normalized: PackedFloat32Array = terrain.map_renderer.normalized_heights
		var actual_water := Water.new()
		check(actual_water.generate(normalized,terrain.sample_size(),terrain.water_source_hash,Water.DEFAULTS).is_empty(),preset+" drainage generates")
		var actual_surface := Surface.new()
		actual_surface.size = terrain.sample_size()
		actual_surface.heights = normalized.duplicate()
		actual_surface.source_hash = terrain.water_source_hash
		var actual_regions := Provinces.new()
		check(actual_regions.generate(normalized,actual_surface,actual_water,8).is_empty() and actual_regions.generate_oceans(normalized,actual_water,8,"coastal_band",64).is_empty(),preset+" supports ocean provinces")
		var sea_regions := 0
		for record in actual_regions.records:
			if record.kind == "ocean" and record.active: sea_regions += 1
		check(sea_regions > 0 and actual_regions.validate_coverage(normalized,0.2,actual_water).is_empty(),preset+" has valid assigned sea regions")
		world.free()
	print("Enclosed seas: %d failures" % failures)
	quit(1 if failures else 0)
