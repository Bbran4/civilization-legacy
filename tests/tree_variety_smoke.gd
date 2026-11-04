extends SceneTree
const Species = preload("res://scripts/domain/tree_species.gd")
const Meshes = preload("res://scripts/rendering/forest_meshes.gd")
const Controls = preload("res://scripts/domain/regional_controls.gd")
const Renderer = preload("res://scripts/rendering/terrain_map_renderer.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://.test-runtime")
	_run.call_deferred()
func mix_for(region: Vector2) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(Species.NAMES.size())
	for i in range(1000): counts[Species.choose(region,0.3,(i+0.5)/1000.0)] += 1
	return counts
func _run() -> void:
	var library := Meshes.library()
	var triangles := 0
	var max_triangles := 0
	for kind in range(library.size()):
		var mesh := library[kind]
		var arrays := mesh.surface_get_arrays(0)
		var count: int = arrays[Mesh.ARRAY_INDEX].size()/3
		triangles += count
		max_triangles = maxi(max_triangles,count)
		check(count > 20 and count <= 300,"Bounded geometry for "+Species.NAMES[kind])
		check(mesh == Meshes.library()[kind],"Species mesh is shared across views")
		var bounds := Meshes.bounds(mesh)
		var contained := true
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			var xz := Vector2(vertex.x,vertex.z)*Meshes.MAX_WIDTH_FACTOR
			xz.x += vertex.y*vertex.y*(Meshes.BEND+Meshes.WIND)
			if xz.length() > bounds.x+0.0001 or vertex.y*Meshes.MAX_HEIGHT_FACTOR > bounds.y+0.0001 or vertex.y < -0.0001: contained = false
		check(contained,"Bounds include crown, shape variation and wind for "+Species.NAMES[kind])
	var cold := mix_for(Vector2(0.15,0.85))
	var hot_wet := mix_for(Vector2(0.92,0.9))
	var hot_dry := mix_for(Vector2(0.92,0.08))
	var mediterranean := mix_for(Vector2(0.55,0.15))
	check(cold[Species.SPRUCE]+cold[Species.BIRCH] > 900,"Cool wet regions favor spruce and birch")
	check(hot_wet[Species.PALM] > 900,"Warm wet regions favor palms")
	check(hot_dry[Species.ACACIA] > 650,"Warm dry regions favor acacia")
	check(mediterranean[Species.OLIVE]+mediterranean[Species.STONE_PINE] > 900,"Mild dry regions favor olive and stone pine")
	var world = load("res://scenes/main.tscn").instantiate()
	var terrain = world.get_node("Terrain")
	terrain.resolution = 128
	terrain.graph_points = 1000
	terrain.map_size = Vector2(96,72)
	root.add_child(world)
	await process_frame
	terrain.elevation = 12
	terrain.regenerate()
	var source := PackedFloat32Array()
	var size: Vector2i = terrain.sample_size()
	source.resize(size.x*size.y)
	source.fill((0.32-0.2)*12)
	terrain.restore_heightfield(source,size)
	var climates := [Vector2(0.5,0.8),Vector2(0.15,0.7),Vector2(0.45,0.9),Vector2(0.6,0.1),Vector2(0.6,0.2),Vector2(0.9,0.05),Vector2(0.9,0.9)]
	var controls := Controls.new().snapshot()
	var bytes := PackedByteArray()
	bytes.resize(Controls.BYTES)
	for y in range(128):
		for x in range(128):
			var climate: Vector2 = climates[mini(6,x*7/128)]
			var i := (y*128+x)*4
			bytes[i] = roundi((climate.x+0.12*0.65)*255)
			bytes[i+1] = roundi(climate.y*255)
			bytes[i+3] = 255
	controls.overrides = Marshalls.raw_to_base64(bytes)
	terrain.regional_controls = Controls.decode(controls).controls
	var settings: Dictionary = terrain.tree_settings.duplicate()
	settings.count = 1500
	settings.coverage = 100
	check(terrain.apply_tree_settings(settings).is_empty(),"Plant regional species fixture")
	var forest = terrain.forest_view
	var all_species := true
	for count in forest.species_counts:
		if count == 0: all_species = false
	check(all_species,"Actual regional forest contains all seven species")
	check(forest.get_child_count() <= 112 and forest.meshes == library,"Seven species retain at most 112 shared-mesh batches")
	var source_unchanged: bool = terrain.height_samples == source
	var positions: PackedVector2Array = forest.positions.duplicate()
	var kinds: PackedByteArray = forest.kinds.duplicate()
	var scales: PackedFloat32Array = forest.scales.duplicate()
	var document: Dictionary = Document.capture(terrain)
	check(Document.apply(terrain,JSON.parse_string(JSON.stringify(document))).is_empty() and forest.positions == positions and forest.kinds == kinds and forest.scales == scales and source_unchanged,"Species and sizes reconstruct deterministically without changing geography")
	world.free()
	await process_frame
	if DisplayServer.get_name() != "headless": await _gallery(library)
	print("Tree variety: %d failures; %d shared species triangles, maximum %d per mesh" % [failures,triangles,max_triangles])
	quit(1 if failures else 0)
func _gallery(library: Array[ArrayMesh]) -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-35,0)
	sun.light_color = Color(1,0.95,0.86)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_mode = 0
	sun.directional_shadow_max_distance = 100
	scene.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.5
	camera.position = Vector3(0,10,7)
	scene.add_child(camera)
	camera.look_at(Vector3(0,0.5,0))
	camera.current = true
	var surface := MeshInstance3D.new()
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(surface)
	var renderer := Renderer.new(surface)
	var source := PackedFloat32Array([0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4])
	renderer.set_heightfield(source,Vector2i(3,3),Vector2(20,8),0,1,2)
	renderer.set_relief(1)
	var environment := Environment.new()
	environment.ambient_light_color = Color(0.76,0.84,0.95)
	environment.ambient_light_energy = 0.38
	renderer.update_lighting(sun,environment,camera,Vector3.ZERO)
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/rendering/forest.gdshader")
	material.set_shader_parameter("tree_detail",1.0)
	renderer.bind_relief_material(material)
	for kind in range(library.size()):
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_custom_data = true
		batch.use_colors = true
		batch.mesh = library[kind]
		batch.instance_count = 3
		for variant in range(3):
			var origin := Vector3((kind-3)*2.25,0,(variant-1)*2.2)
			var scale := 0.80+variant*0.15
			batch.set_instance_transform(variant,Transform3D(Basis(Vector3.UP,variant*1.3).scaled(Vector3.ONE*scale),origin))
			batch.set_instance_custom_data(variant,Color(origin.x/20.0+0.5,origin.z/8.0+0.5,scale,0.14+variant*0.35))
			batch.set_instance_color(variant,Color.WHITE)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.material_override = material
		scene.add_child(instance)
		var label := Label3D.new()
		label.text = Species.NAMES[kind]
		label.font_size = 48
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.no_depth_test = true
		label.position = Vector3((kind-3)*2.25,0.25,3.2)
		scene.add_child(label)
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.test-runtime/tree-species-gallery.png")
	scene.free()
	await process_frame
