extends SceneTree
const Materials = preload("res://scripts/rendering/terrain_materials.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _capture(path: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://.godot/" + path + ".png")
	return image

func _set_enabled(terrain: Node, enabled: bool) -> void:
	for material in [terrain._land_material, terrain.detail._material]:
		material.set_shader_parameter("surface_materials_enabled", enabled)

func _difference(a: Image, b: Image) -> float:
	var total: float = 0
	# Ignore UI; compare the clear middle of the map viewport.
	for y in range(170, 620, 3):
		for x in range(420, 940, 3):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total

func _run() -> void:
	_check(Materials.ensure_library(), "Texture arrays must build on the actual renderer.")
	_check(Materials.albedo.get_layers() == 7 and Materials.normals.get_layers() == 7, "All seven ground surfaces must have albedo and normal/roughness layers.")
	for layer in range(7):
		for uv in [Vector2.ZERO, Vector2(0.31, 0.7), Vector2(0.92, 0.13)]:
			_check(absf(Materials.relief(uv, layer) - Materials.relief(uv + Vector2(1, 0), layer)) < 0.00001 and absf(Materials.relief(uv, layer) - Materials.relief(uv + Vector2(0, 1), layer)) < 0.00001, "Surface relief must tile seamlessly in both axes.")
		var normal: Image = Materials.normals.get_layer_data(layer)
		_check(normal.has_mipmaps(), "Detail normals need mipmaps to avoid distant shimmer.")
		for y in range(0, 128, 16):
			for x in range(0, 128, 16):
				var c: Color = normal.get_pixel(x, y)
				var n := Vector3(c.r, c.g, c.b) * 2.0 - Vector3.ONE
				_check(absf(n.length() - 1.0) < 0.02 and n.z > 0 and c.a >= 0.7, "Packed normals must be unit vectors with valid independent roughness.")
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var terrain = world.get_node("Terrain")
	terrain.map_size = Vector2(512, 384)
	terrain.terrain_template = "Continents"
	terrain.island_enabled = false
	terrain.regenerate()
	world.get_node("Interface/Editor")._sync_from_terrain()
	var rig = world.get_node("CameraRig")
	rig._reset_view()
	var texture_id: int = Materials.albedo.get_instance_id()
	var tint_id: int = terrain._regional_tint.get_instance_id()
	var mesh_id: int = terrain.detail.chunks[0].meshes[0].get_instance_id()
	var field: PackedFloat32Array = terrain.height_samples.duplicate()
	var builds: int = Materials.build_count
	for material in [terrain._land_material, terrain.detail._material]:
		_check(material.get_shader_parameter("surface_albedo").get_instance_id() == texture_id, "Base and LOD must share the same texture library.")
		_check(material.get_shader_parameter("surface_tile_size") == 8.0, "Surface scale must use world units, independent of map dimensions.")
	var options: Dictionary = terrain.climate_settings.duplicate()
	options.latitude_center = 25
	options.latitude_span = 45
	options.rainfall_scale = 1.7
	terrain.apply_climate(options)
	_check(terrain.height_samples == field and terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh_id, "Climate-driven material updates must preserve geometry.")
	_check(terrain._regional_tint.get_instance_id() == tint_id and Materials.build_count == builds, "Climate updates must reuse regional noise and texture assets.")
	var saved: Dictionary = Document.capture(terrain)
	var tint: PackedByteArray = terrain._regional_tint.get_image().get_data()
	_check(Document.apply(terrain, saved).is_empty() and terrain._regional_tint.get_image().get_data() == tint, "Existing saves must reproduce presentation without another saved cache.")
	if DisplayServer.get_name() != "headless":
		await _capture("materials-overview")
		var target: int = 0
		var score: float = -INF
		for cell in range(terrain.graph.count):
			var info: Dictionary = terrain.cell_info(cell)
			if info.surface_kind != "Land" or info.height < 26 or info.height > 48 or info.temperature < 4:
				continue
			var candidate: float = info.canopy + info.water_support * 0.5
			if candidate > score:
				target = cell
				score = candidate
		var point: Vector2 = terrain.graph.points[target] - terrain.map_size * 0.5
		rig.position.x = point.x
		rig.position.z = point.y
		rig._zoom = rig._fit_size / 16.0
		rig._apply_zoom()
		terrain.detail._process(1.0)
		var layered: Image = await _capture("materials-close")
		_set_enabled(terrain, false)
		var plain: Image = await _capture("materials-close-plain")
		var bright: float = 0.0
		var reference: float = 0.0
		for y in range(200, 600, 5):
			for x in range(430, 930, 5):
				bright += layered.get_pixel(x, y).get_luminance()
				reference += plain.get_pixel(x, y).get_luminance()
		_check(bright / maxf(reference, 0.001) < 1.15, "Neutral material multipliers must preserve the base biome brightness in Compatibility.")
		_check(_difference(layered, plain) > 10.0, "Rendered close terrain must visibly use the new surface materials.")
		_set_enabled(terrain, true)
		terrain.set_climate_view(2)
		var climate_a: Image = await _capture("materials-rainfall")
		_set_enabled(terrain, false)
		var climate_b: Image = await _capture("materials-rainfall-plain")
		_check(_difference(climate_a, climate_b) < 0.01, "Rainfall diagnostics must bypass decorative material tint and normals.")
		_set_enabled(terrain, true)
		terrain.set_climate_view(0)
	_check(Materials.albedo.get_instance_id() == texture_id and Materials.build_count == builds, "Zoom and map changes must never regenerate the material library.")
	world.queue_free()
	await process_frame
	print("Terrain material checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
