@tool
extends Node3D
## Isolated Terrain3D workspace. Generation never changes legacy world documents.
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const Detail = preload("res://scripts/domain/heightmap_detail.gd")
const Weathering = preload("res://scripts/domain/mountain_weathering.gd")
const Climate = preload("res://scripts/domain/landscape_climate.gd")
const Hydrology = preload("res://scripts/domain/terrain3d_hydrology.gd")
const InlandWater = preload("res://scripts/rendering/inland_water.gd")
const GRASS_TEXTURE := 0
const CLIFF_TEXTURE := 1

@export_enum("High Island", "Volcano", "Old World", "Mediterranean", "Continents", "Archipelago", "Low Island", "Atoll", "Peninsula", "Pangea", "Isthmus", "Shattered", "Taklamakan", "Fractious", "World heightmap", "Europe heightmap", "Mediterranean heightmap", "Imported heightmap") var template := "High Island":
	set(value):
		template = value
		notify_property_list_changed()
		if is_node_ready():
			_sync_source_controls()
## Used when Template is Imported heightmap. Image values are normalized heights (0–1).
@export_global_file("*.png", "*.exr", "*.jpg", "*.jpeg", "*.webp") var heightmap_file := ""
## Fit Length to the source aspect ratio, rounded to the trial's 256-sample tiles.
@export var match_heightmap_aspect := true
@export var invert_heightmap := false
@export var world_seed := "1324865"
@export_range(256, 4096, 256) var width: int = 1024
@export_range(256, 4096, 256) var length: int = 1024
@export_range(20, 500, 1) var height_range: float = 160.0
## Imported maps only: vertical span is 0.5% of map width at 1x.
## This is a presentation baseline, not a recovered CK3 engine transform.
@export_range(0.1, 4.0, 0.05) var imported_relief: float = 1.0
## Sea datum as a fraction of the generated height range.
@export_range(0, 1, 0.01) var sea_level: float = 0.2
@export_range(0, 1, 0.05) var mountain_detail: float = 0.5
@export_range(0, 1, 0.05) var mountain_weathering: float = 0.35
@export var regional_ground_tint := true
@export_range(0, 2, 0.05) var rainfall: float = 1.0
@export_range(-20, 20, 1) var warmth: float = 0.0
@export_range(0, 360, 5) var prevailing_wind: float = 225.0
@export_range(0.25, 4, 0.25) var river_density: float = 1.5
@export_range(0.5, 4, 0.25) var river_width: float = 1.5
@export_range(0.001, 0.02, 0.001) var channel_depth: float = 0.006
@export_tool_button("Generate / replace trial terrain") var generate_action = generate
@export_tool_button("Save terrain snapshot") var save_action = save_snapshot
@export_tool_button("Refresh terrain appearance (keep heights)") var appearance_action = refresh_appearance
@export_tool_button("Carve rivers and lakes") var water_action = carve_water
@export_tool_button("Inspect generated river (preview camera)") var river_view_action = inspect_river
var last_snapshot := ""
@export_storage var applied_settings: Dictionary = {}
var _status: Label
var _pitch := -55.0
var _yaw := 0.0
var _distance := 950.0
var _focus := Vector3.ZERO
var _preset_control: OptionButton
var _dimension_controls: Dictionary = {}
var _source_label: Label
var _heightmap_source_size := Vector2i.ZERO
var _seed_control: LineEdit
var _water_base: Image
@export_storage var water_base_file := ""
@export_storage var water_result_hash := ""
@export_storage var water_summary: Dictionary = {}

func _validate_property(property: Dictionary) -> void:
	var procedural := Recipe.PRESETS.has(template)
	if (property.name in ["height_range", "mountain_detail", "mountain_weathering"] and not procedural) or (property.name == "imported_relief" and procedural):
		property.usage = PROPERTY_USAGE_STORAGE

func _height_scale() -> float:
	return height_range if Recipe.PRESETS.has(template) else maxf(width, length) * 0.005 * imported_relief

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
	if width < 256 or width > 4096 or length < 256 or length > 4096 or width % 256 != 0 or length % 256 != 0:
		push_error("Trial dimensions must be multiples of 256 between 256 and 4096.")
		return
	if not is_finite(sea_level) or sea_level < 0 or sea_level > 1:
		push_error("Invalid trial height range or sea datum.")
		return
	if Recipe.PRESETS.has(template) and (not is_finite(height_range) or height_range < 20 or height_range > 500 or not is_finite(mountain_detail) or mountain_detail < 0 or mountain_detail > 1):
		push_error("Invalid mountain detail.")
		return
	if not Recipe.PRESETS.has(template) and (not is_finite(imported_relief) or imported_relief < 0.1 or imported_relief > 4.0):
		push_error("Invalid imported relief.")
		return
	if not _valid_landscape_settings():
		return
	var image := _build_height_image()
	if image == null:
		return
	var climate := Climate.new()
	climate.generate(image, sea_level, world_seed, rainfall, warmth, prevailing_wind)
	var color_map: Image = null
	if regional_ground_tint:
		color_map = climate.colors
		color_map.resize(width, length, Image.INTERPOLATE_BILINEAR)
	var terrain: Terrain3D = $Terrain3D
	# Regeneration detaches the previous snapshot. A later editor save cannot overwrite it.
	terrain.data_directory = ""
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		terrain.data.remove_region(region, false)
	terrain.data.update_maps(Terrain3DRegion.TYPE_MAX, true, false)
	terrain.region_size = Terrain3D.SIZE_256
	terrain.mesh_size = 128
	refresh_appearance()
	# Build one complete asset set before publishing it. This also retires old
	# placeholder slots without mixing incompatible texture sizes during updates.
	var generated_assets := Terrain3DAssets.new()
	for i in range(2):
		var kind: String = ["ground037", "rock023"][i]
		var asset := Terrain3DTextureAsset.new()
		asset.name = ["Grass", "Cliff"][i]
		asset.albedo_texture = load("res://assets/terrain3d/%s_alb_ht.png" % kind)
		asset.normal_texture = load("res://assets/terrain3d/%s_nrm_rgh.png" % kind)
		asset.albedo_color = Color(0.67, 0.75, 0.69) if i == 0 else Color(0.52, 0.49, 0.44)
		asset.uv_scale = 0.1
		generated_assets.set_texture_asset(i, asset)
	terrain.assets = generated_assets
	var vertical_scale := _height_scale()
	terrain.data.import_images([image, null, color_map], Vector3.ZERO, -sea_level * vertical_scale, vertical_scale)
	_water_base = null
	water_base_file = ""
	water_result_hash = ""
	water_summary = {}
	var old_water := get_node_or_null("InlandWater")
	if old_water != null:
		remove_child(old_water)
		old_water.queue_free()
	$Sea.mesh = PlaneMesh.new()
	$Sea.mesh.size = Vector2(width, length)
	$Sea.position = Vector3(width * 0.5, 0, length * 0.5)
	applied_settings = {"template": template, "width": width, "length": length, "vertical_scale": vertical_scale, "sea_level": sea_level}
	if Recipe.PRESETS.has(template):
		applied_settings.merge({"seed": world_seed, "height_range": height_range, "mountain_detail": mountain_detail, "mountain_weathering": mountain_weathering})
	else:
		applied_settings.merge({"imported_relief": imported_relief, "heightmap_file": _heightmap_path(), "heightmap_source_size": [_heightmap_source_size.x, _heightmap_source_size.y], "invert_heightmap": invert_heightmap, "match_heightmap_aspect": match_heightmap_aspect})
	applied_settings.climate = {"seed": world_seed, "rainfall": rainfall, "warmth": warmth, "wind": prevailing_wind, "ground_tint": regional_ground_tint}
	_sync_source_controls()
	_frame_world()
	last_snapshot = ""
	_update_camera()
	var description := "seed " + world_seed if Recipe.PRESETS.has(template) else "relief %.2f× · no procedural mountain detail" % imported_relief
	_report("%s · %s · %d × %d samples. Select Terrain3D in the Godot editor to sculpt/paint." % [template, description, width, length])

func _valid_landscape_settings() -> bool:
	for pair in [[rainfall, 0.0, 2.0], [warmth, -20.0, 20.0], [prevailing_wind, 0.0, 360.0], [river_density, 0.25, 4.0], [river_width, 0.5, 4.0], [channel_depth, 0.001, 0.02], [mountain_weathering, 0.0, 1.0]]:
		if not is_finite(pair[0]) or pair[0] < pair[1] or pair[0] > pair[2]:
			_report("Invalid landscape settings; current terrain was kept.")
			return false
	return true

func _native_fingerprint() -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var regions: Array = $Terrain3D.data.get_regions_active()
	regions.sort_custom(func(a, b): return a.location.y < b.location.y if a.location.y != b.location.y else a.location.x < b.location.x)
	for region: Terrain3DRegion in regions:
		hash.update(JSON.stringify([region.location.x, region.location.y]).to_utf8_buffer())
		hash.update(region.get_height_map().get_data())
	return hash.finish().hex_encode()

func _capture_normalized_heights() -> Image:
	var terrain: Terrain3D = $Terrain3D
	var size := Vector2i(applied_settings.width, applied_settings.length)
	var regions: Array = terrain.data.get_regions_active()
	if regions.size() != size.x * size.y / (terrain.region_size * terrain.region_size):
		return null
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	for region: Terrain3DRegion in regions:
		var position := region.location * terrain.region_size
		if not Rect2i(Vector2i.ZERO, size).encloses(Rect2i(position, Vector2i.ONE * terrain.region_size)):
			return null
		image.blit_rect(region.get_height_map(), Rect2i(Vector2i.ZERO, Vector2i.ONE * terrain.region_size), position)
	var values := image.get_data().to_float32_array()
	for i in range(values.size()):
		var normalized := values[i] / float(applied_settings.vertical_scale) + float(applied_settings.sea_level)
		if not is_finite(normalized) or normalized < -0.000001 or normalized > 1.000001:
			return null
		values[i] = clampf(normalized, 0, 1)
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, values.to_byte_array())

func carve_water() -> void:
	if not _valid_landscape_settings() or not applied_settings.has("vertical_scale"):
		_report("Generate a terrain before carving water.")
		return
	var current_hash := _native_fingerprint()
	var base: Image = _water_base if current_hash == water_result_hash else null
	if base == null and current_hash == water_result_hash and not water_base_file.is_empty():
		base = Image.load_from_file(ProjectSettings.globalize_path(water_base_file))
		if base == null:
			_report("The saved pre-carving heightmap is unavailable. Restore it before rebuilding water. Current terrain was kept.")
			return
	if base == null:
		base = _capture_normalized_heights()
	if base == null:
		_report("Water carving requires the complete generated region grid with heights inside its applied range. Current terrain was kept.")
		return
	var datum: float = applied_settings.sea_level
	var scale: float = applied_settings.vertical_scale
	var climate := Climate.new()
	climate.generate(base, datum, world_seed, rainfall, warmth, prevailing_wind)
	var hydraulics := Hydrology.new()
	var error := hydraulics.build(base, datum, climate.runoff, river_density, river_width, channel_depth)
	if not error.is_empty():
		_report(error)
		return
	var result := InlandWater.build(hydraulics, base.get_size(), datum, scale)
	if not result.error.is_empty():
		_report(result.error)
		return
	var values: PackedFloat32Array = hydraulics.heights.duplicate()
	for i in range(values.size()):
		values[i] = (values[i] - datum) * scale
	var image := Image.create_from_data(base.get_width(), base.get_height(), false, Image.FORMAT_RF, values.to_byte_array())
	var terrain: Terrain3D = $Terrain3D
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		region.set_height_map(image.get_region(Rect2i(region.location * terrain.region_size, Vector2i.ONE * terrain.region_size)))
	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT)
	terrain.mesh_size = 128
	var water_node := get_node_or_null("InlandWater") as MeshInstance3D
	if water_node == null:
		water_node = MeshInstance3D.new()
		water_node.name = "InlandWater"
		add_child(water_node)
		water_node.owner = self
	water_node.mesh = result.mesh
	water_node.material_override = result.material
	water_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_base = base
	water_base_file = ""
	water_result_hash = _native_fingerprint()
	water_summary = {"rivers": hydraulics.water.river_reaches, "lakes": hydraulics.water.lake_count, "carved_samples": hydraulics.surface.modified_pixels, "wet_pixels": result.wet_pixels, "rainfall": rainfall, "warmth": warmth, "wind": prevailing_wind, "seed": world_seed, "density": river_density, "width": river_width, "depth": channel_depth}
	if hydraulics.has_river_focus:
		water_summary.river_focus = [hydraulics.river_focus.x, (hydraulics.river_focus.y - datum) * scale, hydraulics.river_focus.z]
	_report("Carved %d river reaches and %d lakes · %d changed ground samples. Save a snapshot to retain the pre-carving source." % [water_summary.rivers, water_summary.lakes, water_summary.carved_samples])

func inspect_river() -> void:
	if not water_summary.has("river_focus"):
		_report("Carve rivers and lakes first to inspect a generated channel.")
		return
	var point: Array = water_summary.river_focus
	_focus = Vector3(point[0], point[1], point[2])
	_distance = clampf(maxf(applied_settings.width, applied_settings.length) * 0.1, 40, 500)
	_update_camera()

func refresh_appearance() -> void:
	# Terrain3D's auto blend is 1 on flat ground (overlay) and falls towards 0
	# on steep/high ground (base). Keep these roles separate from asset ordering.
	var material: Terrain3DMaterial = $Terrain3D.material
	material.world_background = Terrain3DMaterial.NONE
	material.auto_shader_enabled = true
	material.set_shader_param("auto_base_texture", CLIFF_TEXTURE)
	material.set_shader_param("auto_overlay_texture", GRASS_TEXTURE)
	material.set_shader_param("auto_slope", 2.0)
	material.set_shader_param("auto_height_reduction", 0.1)
	material.set_shader_param("blend_sharpness", 0.5)
	material.set_shader_param("flat_terrain_normals", false)
	material.set_shader_param("distant_normal_scale", 2.0)
	material.set_shader_param("mipmap_bias", 0.0)

func _heightmap_path() -> String:
	return Recipe.PRECREATED.get(template, heightmap_file if template == "Imported heightmap" else "")

func _build_height_image() -> Image:
	if Recipe.PRESETS.has(template):
		_heightmap_source_size = Vector2i.ZERO
		var graph := Graph.new()
		graph.generate(Vector2(width, length), 10000, world_seed)
		Recipe.new().generate(graph, template, world_seed)
		var size := Vector2i(width, length)
		var heights: PackedFloat32Array = Detail.refine(graph.rasterize(size, 1), size, world_seed, 0.3, mountain_detail)
		heights = Weathering.apply(heights, size, sea_level, mountain_weathering)
		return Image.create_from_data(width, length, false, Image.FORMAT_RF, heights.to_byte_array())
	var path := _heightmap_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		_report("Choose an existing heightmap image before generating. Current terrain was kept.")
		return null
	var source: Image
	if path.begins_with("res://"):
		var texture = load(path)
		if texture is Texture2D:
			source = texture.get_image()
	else:
		source = Image.load_from_file(path)
	if source == null or source.is_empty():
		_report("Could not read the heightmap image. Current terrain was kept.")
		return null
	if source.is_compressed() and source.decompress() != OK:
		_report("Could not decode the heightmap image. Current terrain was kept.")
		return null
	var output_length := length
	_heightmap_source_size = source.get_size()
	if match_heightmap_aspect:
		output_length = clampi(roundi(float(width) * source.get_height() / source.get_width() / 256.0) * 256, 256, 4096)
	# Convert before resizing: high precision source data never passes through RGB8.
	source.convert(Image.FORMAT_RF)
	source.resize(width, output_length, Image.INTERPOLATE_BILINEAR)
	for y in range(output_length):
		for x in range(width):
			var value := source.get_pixel(x, y).r
			if not is_finite(value):
				_report("Heightmap contains non-finite heights. Current terrain was kept.")
				return null
			value = clampf(value, 0, 1)
			source.set_pixel(x, y, Color(1.0 - value if invert_heightmap else value, 0, 0))
	length = output_length
	return source

func select_heightmap_file(path: String) -> void:
	heightmap_file = path
	template = "Imported heightmap"
	_sync_source_controls()
	notify_property_list_changed()
	_report("Heightmap selected. Click Generate to import it; current terrain is unchanged.")

func _choose_heightmap() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png,*.exr,*.jpg,*.jpeg,*.webp ; Heightmap images"])
	dialog.title = "Choose a heightmap image"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String): select_heightmap_file(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.75)

func _sync_source_controls() -> void:
	if is_instance_valid(_preset_control):
		for i in range(_preset_control.item_count):
			if _preset_control.get_item_text(i) == template:
				_preset_control.select(i)
	for key in _dimension_controls:
		_dimension_controls[key].set_value_no_signal(get(key))
	var procedural := Recipe.PRESETS.has(template)
	if _dimension_controls.has("height_range"):
		_dimension_controls.height_range.get_parent().visible = procedural
		_dimension_controls.mountain_detail.get_parent().visible = procedural
		_dimension_controls.mountain_weathering.get_parent().visible = procedural
		_dimension_controls.imported_relief.get_parent().visible = not procedural
	if is_instance_valid(_seed_control):
		_seed_control.editable = true
		_seed_control.tooltip_text = "Controls generated terrain and climate. Imported height samples are unchanged by the seed."
	if is_instance_valid(_source_label):
		_source_label.text = _heightmap_path()
		if applied_settings.get("heightmap_file", "") == _heightmap_path() and applied_settings.has("heightmap_source_size"):
			var size: Array = applied_settings.heightmap_source_size
			_source_label.text += "\nSource: %d × %d · Terrain: %d × %d\nResizing adds samples, not geographic detail." % [size[0], size[1], applied_settings.width, applied_settings.length]
			_source_label.text += "\nImported relief: %.2f× · vertical span: %.2f\nNo procedural mountain detail applied." % [applied_settings.get("imported_relief", 1.0), applied_settings.get("vertical_scale", 0.0)]

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
	if _water_base != null:
		var base_path := directory.path_join("pre-water.exr")
		error = _water_base.save_exr(base_path, false)
		if error != OK:
			_report("Terrain saved but pre-carving source could not be saved: " + error_string(error))
			return
		water_base_file = base_path
	var water_node := get_node_or_null("InlandWater") as MeshInstance3D
	if water_node != null and water_node.mesh != null:
		var mesh_path := directory.path_join("inland-water.res")
		error = ResourceSaver.save(water_node.mesh, mesh_path, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			_report("Terrain saved but water mesh could not be saved: " + error_string(error))
			return
		water_node.mesh.take_over_path(mesh_path)
		var material_path := directory.path_join("inland-water-material.res")
		error = ResourceSaver.save(water_node.material_override, material_path, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			_report("Terrain saved but water material could not be saved: " + error_string(error))
			return
		water_node.material_override.take_over_path(material_path)
	var manifest := applied_settings.duplicate()
	manifest.merge({"format": "civilization-legacy-terrain3d-trial", "version": 1})
	manifest.hydrology = water_summary.duplicate()
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
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -16
	canvas.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.text = "TERRAIN3D TEST WORKSPACE"
	box.add_child(title)
	var presets := OptionButton.new()
	_preset_control = presets
	for value in Recipe.PRESETS.keys() + Recipe.PRECREATED.keys() + ["Imported heightmap"]:
		presets.add_item(value)
		if value == template:
			presets.select(presets.item_count - 1)
	presets.item_selected.connect(func(index: int): template = presets.get_item_text(index); _sync_source_controls())
	box.add_child(presets)
	var import_button := Button.new()
	import_button.text = "Import heightmap image…"
	import_button.pressed.connect(_choose_heightmap)
	box.add_child(import_button)
	_source_label = Label.new()
	_source_label.custom_minimum_size.x = 340
	_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_source_label)
	var aspect := CheckBox.new()
	aspect.text = "Match heightmap aspect ratio"
	aspect.button_pressed = match_heightmap_aspect
	aspect.toggled.connect(func(value: bool): match_heightmap_aspect = value)
	box.add_child(aspect)
	var seed_field := LineEdit.new()
	_seed_control = seed_field
	seed_field.text = world_seed
	seed_field.placeholder_text = "World seed"
	seed_field.text_changed.connect(func(value: String): world_seed = value)
	box.add_child(seed_field)
	for entry in [["Width", "width", 256, 4096, 256], ["Length", "length", 256, 4096, 256], ["Height range", "height_range", 20, 500, 1], ["Mountain detail", "mountain_detail", 0, 1, 0.05], ["Mountain weathering", "mountain_weathering", 0, 1, 0.05], ["Imported relief (×)", "imported_relief", 0.1, 4.0, 0.05], ["Sea level (fraction)", "sea_level", 0, 1, 0.01], ["Rainfall", "rainfall", 0, 2, 0.05], ["Warmth", "warmth", -20, 20, 1], ["Wind direction", "prevailing_wind", 0, 360, 5], ["River density", "river_density", 0.25, 4, 0.25], ["River width", "river_width", 0.5, 4, 0.25], ["Channel depth", "channel_depth", 0.001, 0.02, 0.001]]:
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
		_dimension_controls[entry[1]] = spin
		spin.value_changed.connect(func(value: float): set(entry[1], value))
		row.add_child(spin)
	for entry in [["Generate / replace trial", generate], ["Carve rivers and lakes", carve_water], ["Inspect generated river", inspect_river], ["Refresh terrain appearance", refresh_appearance]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		box.add_child(button)
	_status = Label.new()
	_status.custom_minimum_size.x = 340
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Wheel: zoom · right drag: orbit\nMiddle drag: pan · F: frame\nSculpting/painting: open this scene in Godot, generate, then select Terrain3D."
	box.add_child(_status)
	_sync_source_controls()

func _update_camera() -> void:
	if not is_inside_tree():
		return
	var direction := Basis(Vector3.UP, deg_to_rad(_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(_pitch)) * Vector3.BACK
	$Camera3D.position = _focus + direction * _distance
	$Camera3D.look_at(_focus)
	# The default 0.05 near plane loses depth precision at continental distances,
	# making the sea and shallow terrain fight even when their heights differ.
	$Camera3D.near = maxf(0.05, _distance / 200.0)
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
