extends SceneTree
const Library = preload("res://scripts/rendering/terrain_tree_library.gd")
const Definition = preload("res://scripts/rendering/tree_definition.gd")
const Catalog = preload("res://scripts/rendering/tree_catalog.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	var terrain = world.get_node("Terrain")
	terrain.tree_population = 100
	root.add_child(world)
	await process_frame
	terrain.map_size = Vector2(256, 192)
	terrain.terrain_template = "Continents"
	terrain.island_enabled = false
	terrain.regenerate()
	var options: Dictionary = terrain.climate_settings.duplicate()
	options.latitude_center = 25
	options.latitude_span = 35
	options.rainfall_scale = 2
	terrain.apply_climate(options)
	var heights: PackedFloat32Array = terrain.height_samples.duplicate()
	var mesh_id: int = terrain.detail.chunks[0].meshes[0].get_instance_id()
	var sparse: int = terrain.vegetation_view.layout.instances.size()
	var editor = world.get_node("Interface/Editor")
	editor._tree_population.get_line_edit().text = "6000"
	await editor._apply_trees()
	var dense: int = terrain.vegetation_view.layout.instances.size()
	_check(dense > sparse * 3 and dense <= 6000 and terrain.tree_population == 6000, "The runtime population control must substantially increase the forest population.")
	_check(editor._tree_status.text.contains("requested 6000"), "The UI must show the requested count separately from actual planting.")
	_check(terrain.height_samples == heights and terrain.detail.chunks[0].meshes[0].get_instance_id() == mesh_id, "Apply trees must not rebuild terrain geometry.")
	var saved: Dictionary = Document.capture(terrain)
	_check(saved.version == 9 and saved.settings.tree_population == 6000 and Document.validate(saved).is_empty(), "Tree population must be stored in current map files.")
	var bad: Dictionary = saved.duplicate(true)
	bad.settings.tree_population = 250001
	_check(not Document.validate(bad).is_empty(), "Tree counts above the supported bound must be rejected before mutation.")
	terrain.apply_tree_population(0)
	_check(terrain.vegetation_view.groups.is_empty() and terrain.vegetation_view.layout.instances.is_empty(), "Zero population must remove every tree.")
	_check(Document.apply(terrain, saved).is_empty() and terrain.tree_population == 6000, "Loading must restore the requested population.")
	for definition in Library.DEFAULT_CATALOG.definitions:
		var scene: Node = definition.scene.instantiate()
		_check(scene.has_node("Detailed") and scene.has_node("Distant"), "Shipped trees must be editable scenes with explicit detail branches.")
		scene.free()
	var custom = Catalog.new()
	custom.definitions.assign(Library.DEFAULT_CATALOG.definitions)
	var desert = Definition.new()
	desert.label = "Desert test variant"
	desert.scene = load("res://assets/trees/dry_woodland.tscn")
	desert.biome_mask = 1 << 4
	desert.canopy_floor = 0.45
	custom.definitions.append(desert)
	terrain.tree_catalog = custom
	options.latitude_center = 0
	options.latitude_span = 10
	options.temperature_bias = 20
	options.rainfall_scale = 0
	terrain.apply_climate(options)
	terrain.apply_tree_population(300)
	var desert_count: int = 0
	for tree in terrain.vegetation_view.layout.instances:
		if tree.kind == 5:
			desert_count += 1
	_check(desert_count > 0, "Adding a catalog definition with a canopy floor must allow custom trees in desert biomes.")
	var before: float = Library.mesh_for(5, false).get_aabb().end.y
	var edited: Node = desert.scene.instantiate()
	edited.get_node("Detailed/Crown").position.y += 1.0
	var packed := PackedScene.new()
	_check(packed.pack(edited) == OK, "Edited tree scenes must remain valid Godot assets.")
	edited.free()
	desert.scene = packed
	terrain.apply_tree_population(300)
	_check(Library.mesh_for(5, false).get_aabb().end.y > before + 0.5, "Apply trees must rebake edited scene geometry rather than retaining the old procedural mesh.")
	_check(terrain.detail.macro_normal_texture != null and terrain._land_material.get_shader_parameter("macro_normals_enabled") and terrain.detail._material.get_shader_parameter("macro_normal_field") == terrain.detail.macro_normal_texture, "Base and LOD terrain must share the fixed high-detail macro normal field.")
	var normal_id: int = terrain.detail.macro_normal_texture.get_instance_id()
	world.get_node("CameraRig")._zoom = 3
	world.get_node("CameraRig")._apply_zoom()
	terrain.detail._process(1)
	_check(terrain.detail.macro_normal_texture.get_instance_id() == normal_id, "Zoom must not regenerate the terrain normal map.")
	print("Tree population: ", sparse, " -> ", dense, "; custom desert trees: ", desert_count)
	world.queue_free()
	await process_frame
	print("Presentation controls checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
