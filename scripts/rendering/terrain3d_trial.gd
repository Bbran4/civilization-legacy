@tool
extends Node3D
## Isolated Terrain3D workspace. Generation never changes legacy world documents.
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const Detail = preload("res://scripts/domain/heightmap_detail.gd")

@export_enum("High Island", "Volcano", "Old World", "Mediterranean", "Continents", "Archipelago", "Low Island", "Atoll", "Peninsula", "Pangea", "Isthmus", "Shattered", "Taklamakan", "Fractious") var template := "High Island"
@export var world_seed := "1324865"
@export_range(256, 2048, 256) var width: int = 1024
@export_range(256, 2048, 256) var length: int = 1024
@export_range(20, 500, 1) var height_range: float = 160.0
## Sea datum as a fraction of the generated height range.
@export_range(0, 1, 0.01) var sea_level: float = 0.2
@export_range(0, 1, 0.05) var mountain_detail: float = 0.5
@export_tool_button("Generate / replace trial terrain") var generate_action = generate
@export_tool_button("Save terrain snapshot") var save_action = save_snapshot
var last_snapshot := ""
@export_storage var applied_settings: Dictionary = {}
var _status: Label
var _pitch := -55.0
var _yaw := 0.0
var _distance := 950.0
var _focus := Vector3.ZERO

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build_controls()
	if $Terrain3D.data.get_region_count() == 0:
		generate()
	_frame_world()
	_update_camera()

func generate() -> void:
	# Reject invalid inspector/programmatic inputs before replacing authored data.
	if not Recipe.PRESETS.has(template) or width < 256 or width > 2048 or length < 256 or length > 2048 or width % 256 != 0 or length % 256 != 0:
		push_error("Trial dimensions must be multiples of 256 between 256 and 2048.")
		return
	if not is_finite(height_range) or height_range < 20 or height_range > 500 or not is_finite(sea_level) or sea_level < 0 or sea_level > 1:
		push_error("Invalid trial height range or sea datum.")
		return
	if not is_finite(mountain_detail) or mountain_detail < 0 or mountain_detail > 1:
		push_error("Invalid mountain detail.")
		return
	var graph := Graph.new()
	graph.generate(Vector2(width, length), 10000, world_seed)
	Recipe.new().generate(graph, template, world_seed)
	var size := Vector2i(width, length)
	var heights: PackedFloat32Array = Detail.refine(graph.rasterize(size, 1), size, world_seed, 0.3, mountain_detail)
	var image := Image.create_from_data(width, length, false, Image.FORMAT_RF, heights.to_byte_array())
	var terrain: Terrain3D = $Terrain3D
	# Regeneration detaches the previous snapshot. A later editor save cannot overwrite it.
	terrain.data_directory = ""
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		terrain.data.remove_region(region, false)
	terrain.data.update_maps(Terrain3DRegion.TYPE_MAX, true, false)
	terrain.region_size = Terrain3D.SIZE_256
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader_enabled = true
	terrain.material.set_shader_param("auto_base_texture", 0)
	terrain.material.set_shader_param("auto_overlay_texture", 1)
	# Build one complete asset set before publishing it. This also retires old
	# placeholder slots without mixing incompatible texture sizes during updates.
	var generated_assets := Terrain3DAssets.new()
	for i in range(2):
		var kind: String = ["ground037", "rock023"][i]
		var asset := Terrain3DTextureAsset.new()
		asset.name = ["Grass", "Cliff"][i]
		asset.albedo_texture = load("res://assets/terrain3d/%s_alb_ht.png" % kind)
		asset.normal_texture = load("res://assets/terrain3d/%s_nrm_rgh.png" % kind)
		asset.albedo_color = Color(0.67, 0.75, 0.69) if i == 0 else Color.WHITE
		asset.uv_scale = 0.1
		generated_assets.set_texture_asset(i, asset)
	terrain.assets = generated_assets
	terrain.data.import_images([image, null, null], Vector3.ZERO, -sea_level * height_range, height_range)
	$Sea.mesh = PlaneMesh.new()
	$Sea.mesh.size = Vector2(width, length)
	$Sea.position = Vector3(width * 0.5, 0, length * 0.5)
	applied_settings = {"template": template, "seed": world_seed, "width": width, "length": length, "height_range": height_range, "sea_level": sea_level, "mountain_detail": mountain_detail}
	_frame_world()
	last_snapshot = ""
	_update_camera()
	_report("%s · seed %s · %d × %d samples. Select Terrain3D in the Godot editor to sculpt/paint." % [template, world_seed, width, length])

func save_snapshot() -> void:
	# Upstream region serialization crashes outside editor mode in the tested release.
	if not Engine.is_editor_hint():
		_report("Save/sculpt in Godot: open terrain3d_trial.tscn, generate, select Terrain3D, then use Save terrain snapshot on the root.")
		return
	var terrain: Terrain3D = $Terrain3D
	if terrain.data.get_region_count() == 0:
		_report("Generate terrain before saving.")
		return
	# Each explicit save gets a fresh directory; original worlds and earlier trials survive.
	var directory := "res://.terrain3d-trials/%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		_report("Cannot create snapshot: " + error_string(error))
		return
	terrain.data.save_directory(directory)
	# Verify native region files before publishing the snapshot path to the scene.
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		var region_file := directory.path_join(Terrain3DUtil.location_to_filename(region.location))
		if not FileAccess.file_exists(region_file):
			_report("Snapshot verification failed. Previous saves remain available.")
			return
	terrain.data_directory = directory
	last_snapshot = directory
	var manifest := applied_settings.duplicate()
	manifest.merge({"format": "civilization-legacy-terrain3d-trial", "version": 1})
	var file := FileAccess.open(directory.path_join("generation.json"), FileAccess.WRITE)
	if file == null:
		_report("Terrain saved, but generation metadata could not be written: " + directory)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	_report("Saved " + directory + ". In the Godot editor, also save this scene (Ctrl+S).")

func _report(message: String) -> void:
	print("Terrain3D trial: " + message)
	if is_instance_valid(_status):
		_status.text = message

func _build_controls() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size.x = 340
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "TERRAIN3D TEST WORKSPACE"
	box.add_child(title)
	var presets := OptionButton.new()
	for value in Recipe.PRESETS:
		presets.add_item(value)
		if value == template:
			presets.select(presets.item_count - 1)
	presets.item_selected.connect(func(index: int): template = presets.get_item_text(index))
	box.add_child(presets)
	var seed_field := LineEdit.new()
	seed_field.text = world_seed
	seed_field.placeholder_text = "World seed"
	seed_field.text_changed.connect(func(value: String): world_seed = value)
	box.add_child(seed_field)
	for entry in [["Width", "width", 256, 2048, 256], ["Length", "length", 256, 2048, 256], ["Height range", "height_range", 20, 500, 1], ["Sea level (fraction)", "sea_level", 0, 1, 0.01]]:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = entry[0]
		label.custom_minimum_size.x = 180
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = entry[2]
		spin.max_value = entry[3]
		spin.step = entry[4]
		spin.value = get(entry[1])
		spin.value_changed.connect(func(value: float): set(entry[1], value))
		row.add_child(spin)
	for entry in [["Generate / replace trial", generate]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		box.add_child(button)
	_status = Label.new()
	_status.custom_minimum_size.x = 340
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Wheel: zoom · right drag: orbit\nMiddle drag: pan · F: frame\nSculpting/painting: open this scene in Godot, generate, then select Terrain3D."
	box.add_child(_status)

func _update_camera() -> void:
	if not is_inside_tree():
		return
	var direction := Basis(Vector3.UP, deg_to_rad(_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(_pitch)) * Vector3.BACK
	$Camera3D.position = _focus + direction * _distance
	$Camera3D.look_at(_focus)
	$Camera3D.far = 12000

func _frame_world() -> void:
	var extent := Vector2(applied_settings.get("width", width), applied_settings.get("length", length))
	_focus = Vector3(extent.x * 0.5, 0, extent.y * 0.5)
	_distance = maxf(extent.x, extent.y) * 1.2

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(10, _distance / 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(6000, _distance * 1.15)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_yaw -= event.relative.x * 0.3
			_pitch = clampf(_pitch - event.relative.y * 0.3, -85, -15)
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_focus -= ($Camera3D.basis.x * event.relative.x - Vector3($Camera3D.basis.z.x, 0, $Camera3D.basis.z.z).normalized() * event.relative.y) * _distance * 0.001
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_frame_world()
	_update_camera()
