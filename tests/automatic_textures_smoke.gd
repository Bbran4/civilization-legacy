extends SceneTree
const Style = preload("res://scripts/domain/terrain_texturing.gd")
const Library = preload("res://scripts/rendering/procedural_ground_textures.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0
var camera: Camera3D
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	_run.call_deferred()
func capture() -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func sample(image: Image,uv: Vector2 = Vector2(0.5,0.5)) -> Color:
	var point := (uv-Vector2.ONE*0.5)*90
	var screen := camera.unproject_position(Vector3(point.x,0,point.y))*Vector2(image.get_size())/root.get_visible_rect().size
	return image.get_pixelv(Vector2i(screen))
func set_normalized(renderer: RefCounted, normalized: PackedFloat32Array, elevation: float) -> void:
	var world := normalized.duplicate()
	for i in range(world.size()): world[i] *= elevation
	renderer.set_heightfield(world,Vector2i(3,3),Vector2(90,90),0,elevation,2)
func _run() -> void:
	var library := Library.new("42",0)
	var repeat := Library.new("42",0)
	var other := Library.new("42",1)
	check(library.textures.size() == 5,"Five generated material tiles")
	for kind in library.textures:
		var image: Image = library.textures[kind].get_image()
		check(image.get_size() == Vector2i(128,128) and image.has_mipmaps(),"Bounded material resolution with mipmaps")
		check(image.get_data() == repeat.textures[kind].get_image().get_data(),"Same seed reproduces "+kind)
		check(image.get_data() != other.textures[kind].get_image().get_data(),"New variation changes "+kind)
	var settings: Dictionary = Style.DEFAULTS.duplicate()
	var bad := settings.duplicate()
	bad.scale = NAN
	check(not Style.validate(bad).is_empty(),"Nonfinite settings rejected")
	bad = settings.duplicate()
	bad.variation = 0.5
	check(not Style.validate(bad).is_empty(),"Fractional variation rejected")
	if DisplayServer.get_name() != "headless":
		var surface := MeshInstance3D.new()
		root.add_child(surface)
		var renderer := Renderer.new(surface)
		var heights := PackedFloat32Array([0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4])
		set_normalized(renderer,heights,12)
		check(renderer.set_texturing(settings,"42",true).is_empty(),"Bind automatic material generation")
		var original_library = renderer._ground_library
		renderer.set_texturing(settings,"42",true)
		check(renderer._ground_library == original_library,"Unchanged materials reuse their generated textures")
		camera = Camera3D.new()
		root.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.position = Vector3(0,100,0)
		camera.rotation_degrees = Vector3(-90,0,0)
		camera.size = 90
		camera.current = true
		var grass := sample(await capture())
		check(grass.g > grass.r,"Gentle land receives grass")
		heights = PackedFloat32Array([0.1,0.24,0.5,0.1,0.24,0.5,0.1,0.24,0.5])
		set_normalized(renderer,heights,12)
		var sand_image := await capture()
		sand_image.save_png("res://.test-runtime/material-sand.png")
		var sand := sample(sand_image,Vector2(0.41,0.5))
		check(sand.r > sand.g and sand.g > sand.b,"Low shores receive sand")
		heights.fill(0.94)
		set_normalized(renderer,heights,12)
		var snow := sample(await capture())
		check(snow.r+snow.g+snow.b > (grass.r+grass.g+grass.b)*1.3,"High elevations receive snow")
		var previous := Color.BLACK
		var first_snow := Color.BLACK
		var last_snow := Color.BLACK
		var max_jump := 0.0
		for i in range(25):
			heights.fill(0.76+i*0.005)
			set_normalized(renderer,heights,12)
			var transition := sample(await capture())
			if i == 0: first_snow = transition
			else: max_jump = maxf(max_jump,Vector3(transition.r-previous.r,transition.g-previous.g,transition.b-previous.b).length())
			previous = transition
			last_snow = transition
		check(max_jump < 0.08 and last_snow.r+last_snow.g+last_snow.b > first_snow.r+first_snow.g+first_snow.b+0.25,"Snowline blends continuously across a rendered elevation sweep")
		heights = PackedFloat32Array([0.21,0.7,0.99,0.21,0.7,0.99,0.21,0.7,0.99])
		set_normalized(renderer,heights,100)
		settings.snow_height = 100.0
		settings.rock_angle = 15.0
		renderer.set_texturing(settings,"42",true)
		var rock := sample(await capture())
		settings.rock_angle = 75.0
		renderer.set_texturing(settings,"42",true)
		var vegetation := sample(await capture())
		check(vegetation.g-vegetation.r > rock.g-rock.r+0.02,"Slope threshold controls exposed rock")
		# Render a real mask boundary on flat ground. Compare only ground pixels;
		# the overlay itself must not be mistaken for a bank-material change.
		heights.fill(0.4)
		set_normalized(renderer,heights,12)
		var dry := await capture()
		var bank_water = load("res://scripts/domain/terrain_water_layer.gd").new()
		bank_water.mask_size = Vector2i(128,128)
		var bank_mask := Image.create(128,128,false,Image.FORMAT_RGBA8)
		bank_mask.fill(Color(0,0,0,0))
		for y in range(128):
			for x in range(61,67): bank_mask.set_pixel(x,y,Color(1,0,0,1))
		bank_water.mask_bytes = bank_mask.get_data()
		renderer.set_water_layer(bank_water,true)
		var river_banks := await capture()
		river_banks.save_png("res://.test-runtime/material-river-banks.png")
		var near := Vector2(0.53,0.5)
		var far := Vector2(0.65,0.5)
		var dry_near := sample(dry,near)
		var damp := sample(river_banks,near)
		check(damp.r+damp.g+damp.b < dry_near.r+dry_near.g+dry_near.b-0.015,"Dry riverbank soil darkens beside the water")
		check(sample(dry,far).is_equal_approx(sample(river_banks,far)),"Bank material influence remains local")
		var horizontal = load("res://scripts/domain/terrain_water_layer.gd").new()
		horizontal.mask_size = Vector2i(128,128)
		bank_mask.rotate_90(CLOCKWISE)
		horizontal.mask_bytes = bank_mask.get_data()
		renderer.set_water_layer(horizontal,true)
		var horizontal_banks := await capture()
		var h_dry := sample(dry,Vector2(0.5,0.53))
		var h_damp := sample(horizontal_banks,Vector2(0.5,0.53))
		check(h_damp.r+h_damp.g+h_damp.b < h_dry.r+h_dry.g+h_dry.b-0.015,"Banks also appear beside horizontal rivers")
		renderer.set_water_layer(bank_water,true)
		renderer.set_water_layer(bank_water,false)
		check(sample(await capture(),near).is_equal_approx(damp),"Hiding water artwork preserves geographic bank placement")
		renderer.set_water_layer(null,false)
		check(sample(await capture(),near).is_equal_approx(dry_near),"Removing water clears derived bank materials")
		var paint = load("res://scripts/domain/map_paint.gd").new()
		paint.image.fill(Color(1,0,1,1))
		paint.refresh()
		renderer.set_paint(paint,true)
		var painted := sample(await capture())
		check(painted.r > painted.g*2 and painted.b > painted.g*2,"Manual paint remains above generated textures")
		var water = load("res://scripts/domain/terrain_water_layer.gd").new()
		water.mask_size = Vector2i(3,3)
		var water_image := Image.create(3,3,false,Image.FORMAT_RGBA8)
		water_image.fill(Color(0,1,0,1))
		water.mask_bytes = water_image.get_data()
		renderer.set_water_layer(water,true)
		var wet := sample(await capture())
		settings.variation = 2
		renderer.set_texturing(settings,"42",true)
		check(sample(await capture()).is_equal_approx(wet) and wet.b > wet.r,"Water is unaffected by texture regeneration")
		renderer.set_water_layer(water,false)
		check(sample(await capture()).r > wet.r+0.1,"Hiding generated water reveals its textured ground bed")
		renderer.set_water_layer(null,false)
		renderer.set_paint(null,false)
		renderer.set_shaded_relief(false)
		var raw := sample(await capture())
		check(absf(raw.r-raw.g) < 0.005 and absf(raw.g-raw.b) < 0.005,"Raw height view remains grayscale")
		surface.free()
		camera.free()
	# Public editor/storage workflow: settings persist; paint and geography survive.
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	var editor = world.get_node("Interface/Editor")
	terrain.map_size = Vector2(192,144)
	terrain.resolution = 128
	terrain.graph_points = 1000
	terrain.regenerate()
	editor._sync_from_terrain()
	editor._select_layer("paint")
	check(terrain.texture_settings.enabled and terrain.map_renderer.material.get_shader_parameter("textures_enabled"),"New worlds texture automatically")
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var fingerprint: String = terrain.water_source_hash
	terrain.map_paint.begin_stroke()
	terrain.map_paint.stamp(Vector2(0.5,0.5),terrain.map_size,12,Color(0.6,0.1,0.1))
	terrain.map_paint.refresh()
	var paint: PackedByteArray = terrain.map_paint.image.get_data()
	var brush = editor._paint_brush
	brush.texture_controls.variation.value = 17
	await process_frame
	brush.apply_textures(true)
	check(terrain.texture_settings.variation == 17 and terrain.height_samples == heights and terrain.water_source_hash == fingerprint and terrain.map_paint.image.get_data() == paint,"Generate textures preserves heights, source identity and manual paint")
	var cached = terrain.map_renderer._ground_library
	editor._camera_rig._zoom = 4
	editor._camera_rig._apply_zoom()
	check(terrain.map_renderer._ground_library == cached,"Zoom does not regenerate material tiles")
	editor._layer_buttons.paint[1].button_pressed = true
	brush.texture_controls.variation.value = 18
	brush.apply_textures(true)
	check(terrain.texture_settings.variation == 17,"Layer lock protects texture choices")
	editor._layer_buttons.paint[1].button_pressed = false
	editor._layer_buttons.paint[0].button_pressed = false
	check(not terrain.map_renderer.material.get_shader_parameter("textures_enabled"),"Ground visibility hides generated textures")
	editor._layer_buttons.paint[0].button_pressed = true
	var path := "res://.test-runtime/automatic-textures.terrain.json"
	check(Document.save_file(path,terrain).is_empty(),"Save automatic texture choices")
	var loaded := Document.load_file(path)
	check(loaded.ok and Document.apply(terrain,loaded.document).is_empty() and terrain.texture_settings.variation == 17 and terrain.map_paint.image.get_data() == paint,"Actual JSON reload restores textures and paint")
	var missing: Dictionary = loaded.document.duplicate(true)
	missing.erase("texture_settings")
	check(not Document.validate(missing).is_empty(),"Current saves cannot silently omit automatic texture choices")
	var legacy: Dictionary = loaded.document.duplicate(true)
	legacy.version = 12
	legacy.erase("texture_settings")
	check(Document.apply(terrain,legacy).is_empty() and not terrain.texture_settings.enabled,"Older saves preserve their original appearance until generation is requested")
	var invalid: Dictionary = loaded.document.duplicate(true)
	invalid.texture_settings.scale = 0
	check(not Document.apply(terrain,invalid).is_empty() and not terrain.texture_settings.enabled,"Bad texture settings fail before changing live terrain")
	brush.sync_textures()
	brush.apply_textures(true)
	await process_frame
	var variation: int = terrain.texture_settings.variation
	brush.new_texture_variation()
	check(terrain.texture_settings.variation == variation+1,"New variation commits one new seed rather than stale SpinBox text")
	if DisplayServer.get_name() != "headless":
		editor._camera_rig._reset_view()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-runtime/automatic-textures-overview.png")
		editor._camera_rig._zoom = 3
		editor._camera_rig._apply_zoom()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-runtime/automatic-textures-close.png")
	world.free()
	print("Automatic terrain textures: %d failures" % failures)
	quit(1 if failures else 0)
