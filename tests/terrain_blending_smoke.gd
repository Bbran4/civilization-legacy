extends SceneTree
const Materials = preload("res://scripts/rendering/terrain_materials.gd")
const Biomes = preload("res://scripts/domain/terrain_biomes.gd")
var failures: int = 0
func _initialize() -> void:
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _capture(name_text: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://.godot/blending-" + name_text + ".png")
	return image
func _difference(a: Image, b: Image) -> float:
	var total: float = 0
	var count: int = 0
	for y in range(180, 620, 3):
		for x in range(350, 930, 3):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / count
func _texture(colour: Color) -> Texture2D:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBAF)
	image.fill(colour)
	return ImageTexture.create_from_image(image)
func _boundary_metrics(image: Image) -> Vector2:
	# Locate the halfway colour contour across a deliberately straight climate boundary.
	var left: Color = image.get_pixel(250, 400)
	var right: Color = image.get_pixel(1030, 400)
	var origin := Vector3(left.r, left.g, left.b)
	var delta := Vector3(right.r, right.g, right.b) - origin
	var positions := PackedFloat32Array()
	var edge: float = 0.0
	for y in range(180, 620, 8):
		var best: float = INF
		var position: float = 0.0
		var strongest: float = 0.0
		for x in range(350, 930):
			var c: Color = image.get_pixel(x, y)
			var value: float = (Vector3(c.r, c.g, c.b) - origin).dot(delta) / maxf(delta.length_squared(), 0.0001)
			if absf(value - 0.5) < best:
				best = absf(value - 0.5)
				position = x
			# Four-pixel slope avoids treating 8-bit capture quantization as a colour seam.
			var previous: Color = image.get_pixel(x - 4, y)
			strongest = maxf(strongest, Vector3(c.r - previous.r, c.g - previous.g, c.b - previous.b).length() / 4.0)
		positions.append(position)
		edge += strongest
	var mean: float = 0.0
	for position in positions:
		mean += position / positions.size()
	var variance: float = 0.0
	for position in positions:
		variance += pow(position - mean, 2) / positions.size()
	return Vector2(sqrt(variance), edge / positions.size())

func _run() -> void:
	_check(Materials.ensure_library() and Materials.transition_noise != null and Materials.transition_noise.get_image().has_mipmaps(), "Transition masks must use a shared mipmapped numeric noise field.")
	if DisplayServer.get_name() != "headless":
		var fixture := Node3D.new()
		root.add_child(fixture)
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		settings.background_mode = Environment.BG_COLOR
		settings.background_color = Color.BLACK
		environment.environment = settings
		fixture.add_child(environment)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 96
		camera.near = 0.01
		camera.far = 100
		fixture.add_child(camera)
		camera.position = Vector3(0, 40, 0)
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		camera.current = true
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(128, 96)
		var material := ShaderMaterial.new()
		material.shader = load("res://scripts/rendering/terrain.gdshader")
		Materials.bind_library(material, "blend-fixture")
		material.set_shader_parameter("map_size", mesh.size)
		material.set_shader_parameter("height_scale", 100.0)
		material.set_shader_parameter("sea_level", -4.0)
		material.set_shader_parameter("overview_blend", 1.0)
		material.set_shader_parameter("biomes_enabled", true)
		material.set_shader_parameter("biome_palette", ImageTexture.create_from_image(Biomes.palette_image()))
		material.set_shader_parameter("climate_field", _texture(Color(95.0 / 140.0, 1200.0 / 6000.0, 0.5, 0.5)))
		material.set_shader_parameter("habitats_enabled", true)
		material.set_shader_parameter("habitat_field", _texture(Color(0, 0, 0, 0.3)))
		var surface := MeshInstance3D.new()
		surface.mesh = mesh
		surface.material_override = material
		fixture.add_child(surface)
		var patch: Image = await _capture("uniform-patches")
		material.set_shader_parameter("terrain_blending_enabled", false)
		var plain: Image = await _capture("uniform-plain")
		_check(_difference(patch, plain) > 0.005, "Uniform forest climate must gain visible material patches rather than only a blurred climate boundary.")
		material.set_shader_parameter("terrain_blending_enabled", true)
		mesh.size = Vector2(256, 192)
		material.set_shader_parameter("map_size", mesh.size)
		var resized: Image = await _capture("world-scale")
		_check(_difference(patch, resized) < 0.001, "The same physical ground patch must keep its pattern when map dimensions double.")
		Materials.bind_library(material, "different-blend-seed")
		var other: Image = await _capture("other-seed")
		_check(_difference(resized, other) > 0.003, "A different map seed must produce a different transition pattern.")
		Materials.bind_library(material, "blend-fixture")
		var repeat: Image = await _capture("repeat")
		_check(_difference(resized, repeat) < 0.00001, "The same seed and world coordinates must reproduce identical blending.")
		# Regression: tiny palette smoothing previously left these contacts nearly straight.
		camera.size = 96
		mesh.size = Vector2(128, 96)
		material.set_shader_parameter("map_size", mesh.size)
		material.set_shader_parameter("habitat_field", _texture(Color(0, 0, 0, 0)))
		for contact in ["forest-dry", "hot-desert"]:
			var boundary := Image.create(129, 97, false, Image.FORMAT_RGBAF)
			for y in range(97):
				for x in range(129):
					var temperature: float = lerpf(16, 24, x / 128.0) if contact == "forest-dry" else 25.0
					var rain: float = 1000.0 if contact == "forest-dry" else lerpf(100, 600, x / 128.0)
					boundary.set_pixel(x, y, Color((temperature + 80.0) / 140.0, rain / 6000.0, 0.5, 0.5))
			material.set_shader_parameter("climate_field", ImageTexture.create_from_image(boundary))
			material.set_shader_parameter("terrain_blending_enabled", false)
			var before: Image = await _capture(contact + "-before")
			material.set_shader_parameter("terrain_blending_enabled", true)
			var after: Image = await _capture(contact + "-after")
			var old_metrics: Vector2 = _boundary_metrics(before)
			var new_metrics: Vector2 = _boundary_metrics(after)
			print(contact, " contour spread / strongest edge: ", old_metrics, " -> ", new_metrics)
			_check(new_metrics.x > old_metrics.x + 2.0, contact + " must gain a visibly irregular colour boundary, not just interior grain.")

		# Real shader regressions for the two bypass paths shown in the user's screenshots.
		material.set_shader_parameter("climate_field", _texture(Color(95.0 / 140.0, 1200.0 / 6000.0, 0.5, 0.5)))
		for contact in ["beach", "wetland-margin", "woodland-margin"]:
			material.set_shader_parameter("habitat_field", _texture(Color(0, 0, 0, 0)))
			material.set_shader_parameter("sea_level", -4.0)
			if contact == "beach":
				var ramp := PlaneMesh.new()
				ramp.size = mesh.size
				ramp.subdivide_width = 64
				var arrays: Array = ramp.get_mesh_arrays()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for index in range(vertices.size()):
					vertices[index].y = 1.8 + vertices[index].x * 0.04
				arrays[Mesh.ARRAY_VERTEX] = vertices
				var ramp_mesh := ArrayMesh.new()
				ramp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				surface.mesh = ramp_mesh
				material.set_shader_parameter("sea_level", 0.0)
			else:
				surface.mesh = mesh
				material.set_shader_parameter("climate_field", _texture(Color(95.0 / 140.0, 100.0 / 6000.0, 0.5, 0.5)))
				var margin := Image.create(129, 97, false, Image.FORMAT_RGBAF)
				for y in range(97):
					for x in range(129):
						var mask: float = 1.0 if x >= 64 else 0.0
						margin.set_pixel(x, y, Color(mask * 0.7, mask if contact == "wetland-margin" else 0.0, mask if contact == "woodland-margin" else 0.0, mask * 0.5))
				material.set_shader_parameter("habitat_field", Materials.habitat_texture(margin))
			material.set_shader_parameter("terrain_blending_enabled", false)
			var before: Image = await _capture(contact + "-before")
			material.set_shader_parameter("terrain_blending_enabled", true)
			var after: Image = await _capture(contact + "-after")
			# Inspect actual production coverage in black/white: interior grain cannot pass this check.
			var debug_shader := Shader.new()
			var production: String = material.shader.code
			var channel: String = "beach" if contact == "beach" else ("habitat.g" if contact == "wetland-margin" else "habitat.b")
			debug_shader.code = production.substr(0, production.rfind("}")) + "\nALBEDO = vec3(0.0); EMISSION = vec3(" + channel + ");\n}\n"
			var production_shader: Shader = material.shader
			material.shader = debug_shader
			material.set_shader_parameter("terrain_blending_enabled", false)
			var mask_before: Image = await _capture(contact + "-mask-before")
			material.set_shader_parameter("terrain_blending_enabled", true)
			var mask_after: Image = await _capture(contact + "-mask-after")
			var old_boundary: Vector2 = _boundary_metrics(mask_before)
			var patched_boundary: Vector2 = _boundary_metrics(mask_after)
			print(contact, " coverage contour spread: ", old_boundary.x, " -> ", patched_boundary.x)
			_check(patched_boundary.x > old_boundary.x + 2.0, contact + " must break its straight coverage boundary into visible patches.")
			material.shader = production_shader

		surface.mesh = mesh
		material.set_shader_parameter("sea_level", -4.0)
		material.set_shader_parameter("habitat_field", _texture(Color(0, 0, 0, 0.3)))
		var gradient := Image.create(129, 97, false, Image.FORMAT_RGBAF)
		for y in range(97):
			for x in range(129):
				gradient.set_pixel(x, y, Color(95.0 / 140.0, lerpf(100, 1600, x / 128.0) / 6000.0, 0.5, 0.5))
		material.set_shader_parameter("climate_field", ImageTexture.create_from_image(gradient))
		await _capture("transition-overview")
		camera.size = 24
		await _capture("transition-close")
		material.set_shader_parameter("terrain_blending_enabled", false)
		await _capture("transition-before")
		material.set_shader_parameter("terrain_blending_enabled", true)
		material.set_shader_parameter("climate_mode", 2)
		var data_a: Image = await _capture("diagnostic-on")
		material.set_shader_parameter("terrain_blending_enabled", false)
		var data_b: Image = await _capture("diagnostic-off")
		_check(_difference(data_a, data_b) < 0.00001, "Rainfall diagnostics must bypass all appearance warp and noise.")
		material.set_shader_parameter("climate_mode", 0)
		material.set_shader_parameter("heightmap_view", true)
		var height_a: Image = await _capture("height-off")
		material.set_shader_parameter("terrain_blending_enabled", true)
		var height_b: Image = await _capture("height-on")
		_check(_difference(height_a, height_b) < 0.00001, "Height inspection must remain identical with blending on and off.")
		fixture.queue_free()
		await process_frame
	var world = load("res://scenes/main.tscn").instantiate()
	var terrain = world.get_node("Terrain")
	terrain.tree_population = 0
	root.add_child(world)
	await process_frame
	terrain.map_size = Vector2(256, 192)
	terrain.terrain_template = "Continents"
	terrain.island_enabled = false
	terrain.regenerate()
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var ids: PackedByteArray = terrain.biomes.ids.duplicate()
	var climate: PackedFloat32Array = terrain.climate.field.duplicate()
	var flow: PackedFloat64Array = terrain.hydrology.flow.duplicate()
	var geography: Dictionary = terrain.geography.snapshot()
	var mesh_id: int = terrain.detail.chunks[0].meshes[0].get_instance_id()
	var offset: Vector2 = terrain._land_material.get_shader_parameter("blend_seed_offset")
	_check(terrain.detail._material.get_shader_parameter("blend_seed_offset") == offset and terrain.detail._material.get_shader_parameter("transition_noise") == Materials.transition_noise, "Every terrain LOD must share the seeded transition field.")
	var rig = world.get_node("CameraRig")
	for zoom in [1, 3, 10]:
		rig._zoom = zoom
		rig._apply_zoom()
		terrain.detail._process(1)
		_check(terrain.height_samples == heights and terrain.biomes.ids == ids and terrain.climate.field == climate and terrain.hydrology.flow == flow and terrain.geography.snapshot() == geography, "Appearance blending and zoom must preserve terrain, climate, biome and water facts.")
		_check(terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh_id and terrain.detail._material.get_shader_parameter("blend_seed_offset") == offset, "Zoom must keep the mesh and blending pattern inputs fixed.")
	if DisplayServer.get_name() != "headless":
		world.get_node("Interface/Editor")._sync_from_terrain()
		rig._reset_view()
		await _capture("map-overview")
		var candidate: int = 0
		var best: float = INF
		for cell in range(terrain.graph.count):
			var info: Dictionary = terrain.cell_info(cell)
			if info.surface_kind == "Land" and info.temperature > 4 and info.height > 24 and info.height < 60:
				var score: float = absf(info.moisture_ratio - 0.8) if info.has("moisture_ratio") else absf(info.rainfall - 900)
				if score < best:
					candidate = cell
					best = score
		var point: Vector2 = terrain.graph.points[candidate] - terrain.map_size * 0.5
		rig.position.x = point.x
		rig.position.z = point.y
		rig._zoom = rig._fit_size / 24.0
		rig._apply_zoom()
		terrain.detail._process(1)
		await _capture("map-close")
	world.queue_free()
	await process_frame
	print("Terrain blending checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
