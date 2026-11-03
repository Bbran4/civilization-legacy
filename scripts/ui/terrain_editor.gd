extends Control
## Runtime controls stage generation settings; save/load operate on the visible map.

const MaterialPanel = preload("res://scripts/ui/terrain_material_panel.gd")
const GroundBrush = preload("res://scripts/ui/terrain_brush.gd")
const WorldProject = preload("res://scripts/storage/world_project.gd")
const LayerGraph = preload("res://scripts/domain/map_layer_graph.gd")
const Manifest = preload("res://scripts/storage/world_manifest.gd")
var layers: Array = Manifest.default_layers()
var selected_layer := "heightmap"
var _terrain_path := ""
var _gameplay_map: Node3D
var _editor_process_mode: ProcessMode
var _world_path := ""
var dirty := true
var _tracking_changes := false
var _world_status: Label
var _dependency_status: Label
var _unsaved_dialog: ConfirmationDialog
var _pending_action: Callable
var _resume_after_save := false
var _contexts: Dictionary = {}
var _layer_buttons: Dictionary = {}
var _layer_selectors: Dictionary = {}
var _context_host: VBoxContainer
var _climate_panel: PanelContainer
var _toolbar: HBoxContainer
var _material_panel: Window
var _brush: Node

const ClimatePanel = preload("res://scripts/ui/climate_panel.gd")
const Help = preload("res://scripts/ui/terrain_editor_help.gd")
const GenerationProfile = preload("res://scripts/domain/terrain_generation_profile.gd")
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var _terrain: Node
var _camera_rig: Node
var _controls: Dictionary = {}
var _form: VBoxContainer
var _zoom_status: Label
var _status: Label
var _description: Label
var _preview: TextureRect
var _syncing: bool = false
var _pending_image: Texture2D
var _image_path: String = ""
var _dialog: FileDialog
var _dialog_action: String = ""
var _selected_cell: int = -1
var _selected_point := Vector2.INF
var _cell_panel: PanelContainer
var _cell_label: Label
var _tree_population: SpinBox
var _tree_status: Label
var _custom_index: int = -1
var _image_size := Vector2i.ZERO


func _ready() -> void:
	_terrain = get_parent().get_parent().get_node("Terrain")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_rig = get_parent().get_parent().get_node("CameraRig")
	_build_interface()
	_camera_rig.zoom_changed.connect(_update_zoom_status)
	_terrain.vegetation_changed.connect(_update_tree_status)
	_sync_from_terrain()
	_update_zoom_status()
	_terrain.terrain_regenerated.connect(_update_preview)
	_update_preview()
	_terrain.terrain_regenerated.connect(_apply_layer_visibility)
	_build_cell_inspector()
	if not _terrain.heightmap_only:
		var climate_panel := ClimatePanel.new()
		climate_panel.terrain = _terrain
		climate_panel.editor = self
		_climate_panel = climate_panel
		_contexts["climate"].add_child(climate_panel)
		climate_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		climate_panel.custom_minimum_size.y = 450
		climate_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_select_layer("heightmap")
	_setup_document_tracking()


func _build_interface() -> void:
	var editor_theme := Theme.new()
	editor_theme.default_font_size = 14
	editor_theme.set_color("font_color", "Label", Color("dce5e9"))
	theme = editor_theme
	var panel := PanelContainer.new()
	panel.name = "PropertiesPanel"
	panel.anchor_bottom = 1.0
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -370
	panel.offset_top = 60
	panel.offset_right = -14
	panel.offset_bottom = -14
	var background := StyleBoxFlat.new()
	background.bg_color = Color("14212c")
	background.corner_radius_top_left = 12
	background.corner_radius_top_right = 12
	background.corner_radius_bottom_left = 12
	background.corner_radius_bottom_right = 12
	background.content_margin_left = 16
	background.content_margin_right = 16
	background.content_margin_top = 16
	background.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", background)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 9)
	scroll.add_child(_form)
	_build_shell()
	_contexts["heightmap"] = _form
	_label("CIVILIZATION LEGACY", 13, Color("afbdc6"))
	_label("Heightmap editor" if _terrain.heightmap_only else "World editor", 28, Color("f0dbab"))
	_label("Create a heightmap. Keep the world.", 14)
	var files := HBoxContainer.new()
	_toolbar.add_child(files)
	_button("Save terrain…", func(): _show_dialog("save"), files, "SaveTerrain")
	_button("Load terrain…", func(): _show_dialog("load"), files, "LoadTerrain")
	_section("CREATE A MAP")
	_label("Heightmap", 13)
	var preset := OptionButton.new()
	preset.name = "Preset"
	for title in ["Noise"] + Recipe.PRESETS.keys() + Recipe.PRECREATED.keys():
		preset.add_item(title)
		preset.set_item_metadata(preset.item_count - 1, title)
		preset.get_popup().set_item_tooltip(preset.item_count - 1, Help.DESCRIPTIONS[title])
	_custom_index = preset.item_count
	preset.add_item("Imported heightmap")
	preset.set_item_metadata(_custom_index, "Noise")
	preset.set_item_disabled(_custom_index, true)
	_controls["terrain_template"] = preset
	_form.add_child(preset)
	preset.item_selected.connect(_preset_selected)
	_description = _label("", 13, Color("a9bdc8"))
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("Import heightmap image…", func(): _show_dialog("image"))
	_number("Width (east–west)", "map_size.x", 8, 8192, 1)
	_number("Height (north–south)", "map_size.y", 8, 8192, 1)
	var seed_label := _label("Seed", 13)
	_help(seed_label, "map_seed")
	var seed_input := LineEdit.new()
	seed_input.name = "MapSeed"
	seed_input.placeholder_text = "A number or a name"
	seed_input.max_length = 128
	seed_input.text_changed.connect(func(_text: String): _settings_changed())
	_form.add_child(seed_input)
	_controls["map_seed"] = seed_input
	var island := CheckBox.new()
	island.text = "Island shaping"
	island.toggled.connect(func(_enabled: bool): _settings_changed())
	_form.add_child(island)
	_controls["island_enabled"] = island
	_number("Elevation (relief)", "elevation", 1, 100, 0.5)
	if _terrain.heightmap_only:
		_controls["elevation"].get_parent().visible = false
		_number("Coast detail", "coast_detail", 0, 1, 0.05)
		_number("Mountain detail", "mountain_detail", 0, 1, 0.05)
		_label("Output resolution")
		var output := OptionButton.new()
		for pixels in [512, 1024]:
			output.add_item(str(pixels + 1) + " px longest edge")
			output.set_item_metadata(output.item_count - 1, pixels)
		output.select(1)
		output.item_selected.connect(func(_index: int): _settings_changed())
		_controls["heightmap_resolution"] = output
		_form.add_child(output)
		var raw := CheckBox.new()
		raw.name = "RawHeightView"
		raw.text = "Raw height values (editor only)"
		raw.tooltip_text = "Inspect unshaded height values. Play map always uses the shared shaded-relief presentation. Exports remain raw height data."
		raw.toggled.connect(_terrain.set_raw_height_view)
		_form.add_child(raw)
		_button("Export grayscale PNG…", func(): _show_dialog("export"))
	var actions := HBoxContainer.new()
	_form.add_child(actions)
	_button("Generate", apply_settings, actions, "Generate")
	_button("New seed", _new_seed, actions, "NewSeed")
	var automatic := _label("Black = lowest · White = highest · Sea datum 20%" if _terrain.heightmap_only else "Terrain detail and colours are chosen automatically.", 13, Color("a9bdc8"))
	automatic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status = _label("Ready", 13, Color("d7c18d"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(0, 125)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_form.add_child(_preview)
	_help(_preview, "preview")
	_context("trees")
	_section("TREES")
	_label("Requested tree population", 13)
	_tree_population = SpinBox.new()
	_tree_population.name = "TreePopulation"
	_tree_population.min_value = 0
	_tree_population.max_value = 250000
	_tree_population.step = 1
	_set_hint(_tree_population, "Choose how many trees to try to plant; water, cliffs and crowded ground can leave fewer places.")
	_form.add_child(_tree_population)
	_button("Apply trees", _apply_trees, null, "ApplyTrees")
	_tree_status = _label("", 12, Color("a9bdc8"))
	_tree_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context("ground")
	_brush = GroundBrush.new()
	add_child(_brush)
	_brush.configure(self)
	_context("view")
	_section("VIEW")
	_number("Minimum zoom (×)", "min_zoom", 0.1, 1, 0.1, true)
	_number("Maximum zoom (×)", "max_zoom", 1, 8192, 1, true)
	_number("Closest view size", "closest_view_size", 0.5, 128, 0.5, true)
	_zoom_status = _label("", 12, Color("a9bdc8"))
	_zoom_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var zoom_actions := HBoxContainer.new()
	_form.add_child(zoom_actions)
	_button("Farthest view", func(): _camera_rig.zoom_to_limit(false), zoom_actions, "FarthestView")
	_button("Closest view", func(): _camera_rig.zoom_to_limit(true), zoom_actions, "ClosestView")
	var view := CheckBox.new()
	view.text = "Show heights"
	view.visible = not _terrain.heightmap_only
	view.toggled.connect(_terrain.set_heightmap_view)
	_form.add_child(view)
	_help(view, "grayscale")
	_button("Export grayscale PNG…", func(): _show_dialog("export"))
	var instructions := _label("Wheel: zoom · WASD / middle-drag: move\nZoom in, then right-drag to turn or tilt\nF: full map · Save before generating again", 12, Color("a9bdc8"))
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.size = Vector2i(850, 560)
	_dialog.file_selected.connect(_file_selected)
	add_child(_dialog)
	for key in _controls:
		_help(_controls[key], key)
		if _controls[key] is SpinBox:
			_help(_controls[key].get_parent(), key)
	_context("rivers")
	_label("Rivers / lakes", 22)
	_label("Generated from height and climate. Independent river authoring is planned.").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context("climate")
	_form = _contexts["heightmap"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://maps"))



func _help(control: Control, key: String) -> void:
	assert(Help.HINTS.has(key), "Missing editor help: " + key)
	_set_hint(control, Help.HINTS[key])


func _set_hint(control: Control, hint: String) -> void:
	control.tooltip_text = hint
	for child in control.get_children(true):
		if child is Control:
			_set_hint(child, hint)


func _label(text: String, size: int = 14, color: Color = Color("dce5e9")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_form.add_child(label)
	return label


func _section(title: String) -> void:
	_form.add_child(HSeparator.new())
	_label(title, 12, Color("d7c18d"))


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	_form.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _number(title: String, key: String, minimum: float, maximum: float, step: float, live_zoom: bool = false) -> void:
	var row: HBoxContainer = _row(title)
	var spin := SpinBox.new()
	spin.name = key.replace(".", "_")
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.custom_minimum_size.x = 125
	spin.select_all_on_focus = true
	spin.update_on_text_changed = live_zoom
	if live_zoom:
		spin.value_changed.connect(func(_value: float): _zoom_limits_changed())
	else:
		spin.value_changed.connect(func(_value: float): _settings_changed())
	row.add_child(spin)
	_controls[key] = spin


func _button(title: String, action: Callable, parent: Node = null, node_name: String = "") -> void:
	var button := Button.new()
	button.text = title
	if Help.HINTS.has(title):
		_help(button, title)
	if not node_name.is_empty():
		button.name = node_name
	button.custom_minimum_size.y = 32
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	(parent if parent != null else _form).add_child(button)


func _sync_from_terrain() -> void:
	_syncing = true
	_tree_population.set_value_no_signal(_terrain.tree_population)
	_update_tree_status()
	if _terrain.heightmap_only:
		_controls["coast_detail"].set_value_no_signal(_terrain.coast_detail)
		_controls["mountain_detail"].set_value_no_signal(_terrain.mountain_detail)
		var output: OptionButton = _controls["heightmap_resolution"]
		output.select(0 if _terrain.resolution == 512 else 1)
	(_controls["map_seed"] as LineEdit).text = _terrain.map_seed
	(_controls["map_size.x"] as SpinBox).set_value_no_signal(_terrain.map_size.x)
	(_controls["map_size.y"] as SpinBox).set_value_no_signal(_terrain.map_size.y)
	(_controls["island_enabled"] as CheckBox).set_pressed_no_signal(_terrain.island_enabled)
	(_controls["elevation"] as SpinBox).set_value_no_signal(_terrain.elevation)
	(_controls["min_zoom"] as SpinBox).set_value_no_signal(_camera_rig.min_zoom)
	(_controls["max_zoom"] as SpinBox).set_value_no_signal(_camera_rig.max_zoom)
	(_controls["closest_view_size"] as SpinBox).set_value_no_signal(_camera_rig.closest_view_size)
	_pending_image = _terrain.heightmap_texture
	_image_path = _terrain.source_heightmap_path
	_image_size = _terrain.source_heightmap_size
	var picker := _controls["terrain_template"] as OptionButton
	picker.set_item_disabled(_custom_index, _pending_image == null)
	if _pending_image != null:
		picker.select(_custom_index)
	else:
		for i in range(_custom_index):
			if picker.get_item_metadata(i) == _terrain.terrain_template:
				picker.select(i)
	_update_description()
	_syncing = false


func _apply_trees() -> void:
	if not can_edit("trees"):
		return
	_tree_population.apply()
	await get_tree().process_frame
	if not can_edit("trees"):
		return
	_terrain.apply_tree_population(int(_tree_population.value))
	_update_tree_status()
	_refresh_selected_cell()

func _update_tree_status() -> void:
	if _tree_status == null:
		return
	var actual: int = _terrain.vegetation_view.layout.instances.size() if _terrain.vegetation_view != null and _terrain.vegetation_view.layout != null else 0
	_tree_status.text = "Placed %d / requested %d" % [actual, _terrain.tree_population]
	if actual < _terrain.tree_population:
		_tree_status.text += "\nLimited by suitable ground, spacing and placement budget."


func _zoom_limits_changed() -> void:
	if _syncing:
		return
	_camera_rig.min_zoom = _controls["min_zoom"].value
	_camera_rig.max_zoom = _controls["max_zoom"].value
	_camera_rig.closest_view_size = _controls["closest_view_size"].value
	_update_zoom_status()


func _update_zoom_status() -> void:
	if _zoom_status == null:
		return
	var limits: Vector2 = _camera_rig.zoom_limits()
	var cap: String = "Closest view size limits zoom-in." if limits.y < _camera_rig.max_zoom else "Maximum zoom limits zoom-in."
	_zoom_status.text = "Now %.1f× · Allowed %.1f×–%.1f×\n%s\nUse the wheel or the view buttons to try these limits." % [_camera_rig._zoom, limits.x, limits.y, cap]


func _settings_changed() -> void:
	if not _syncing:
		_status.text = "Ready to create your next map. Press Generate to apply changes."


func _preset_selected(index: int) -> void:
	if _syncing:
		return
	if index != _custom_index:
		_pending_image = null
		_image_path = ""
		_image_size = Vector2i.ZERO
		(_controls["terrain_template"] as OptionButton).set_item_disabled(_custom_index, true)
	_update_description()
	_settings_changed()


func _update_description() -> void:
	var picker := _controls["terrain_template"] as OptionButton
	_description.text = "Imported: " + _image_path.get_file() if picker.selected == _custom_index else Help.DESCRIPTIONS[picker.get_item_text(picker.selected)]
	if _terrain.heightmap_only:
		var raster: bool = picker.selected == _custom_index or Recipe.PRECREATED.has(picker.get_item_metadata(picker.selected))
		_controls["coast_detail"].editable = not raster
		_controls["mountain_detail"].editable = not raster
		_controls["island_enabled"].disabled = raster
		if raster:
			_controls["island_enabled"].set_pressed_no_signal(false)
			_description.text += "\nImported height data is preserved without procedural embellishment."


func apply_settings() -> void:
	var error := regeneration_error("heightmap")
	if not error.is_empty():
		_status.text = error
		return
	var picker := _controls["terrain_template"] as OptionButton
	_terrain.terrain_template = picker.get_item_metadata(picker.selected)
	_terrain.map_size = Vector2(_controls["map_size.x"].value, _controls["map_size.y"].value)
	_terrain.map_seed = (_controls["map_seed"] as LineEdit).text
	_terrain.heightmap_texture = _pending_image
	_terrain.source_heightmap_path = _image_path
	_terrain.source_heightmap_size = _image_size
	GenerationProfile.apply(_terrain)
	if _terrain.heightmap_only:
		_terrain.coast_detail = _controls["coast_detail"].value
		_terrain.mountain_detail = _controls["mountain_detail"].value
		var output: OptionButton = _controls["heightmap_resolution"]
		_terrain.resolution = output.get_item_metadata(output.selected)
	_terrain.island_enabled = (_controls["island_enabled"] as CheckBox).button_pressed
	_terrain.elevation = _controls["elevation"].value
	_terrain.snow_height = _terrain.elevation * 0.55
	_terrain.regenerate()
	# Normalize an empty seed in the control to match the generated map.
	(_controls["map_seed"] as LineEdit).text = _terrain.map_seed
	_update_preview()
	get_parent().get_parent().get_node("CameraRig")._reset_view()


func _new_seed() -> void:
	if not regeneration_error("heightmap").is_empty():
		_status.text = regeneration_error("heightmap")
		return
	(_controls["map_seed"] as LineEdit).text = str(randi_range(1, 2147483647))
	apply_settings()


func _update_preview() -> void:
	_preview.texture = ImageTexture.create_from_image(_terrain.heightmap_image())
	_status.text = "Current map: %s\n%d × %d · Seed %s\nCreated in %.2f seconds" % [_terrain.source_heightmap_path.get_file() if _terrain.heightmap_texture != null else _terrain.terrain_template, _terrain.map_size.x, _terrain.map_size.y, _terrain.map_seed, _terrain.generation_ms / 1000.0]


func _show_dialog(action: String) -> void:
	_dialog_action = action
	_dialog.current_dir = ProjectSettings.globalize_path("user://maps")
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action in ["load", "image", "load_world"] else FileDialog.FILE_MODE_SAVE_FILE
	match action:
		"save_world", "load_world":
			_dialog.title = "Save current world" if action == "save_world" else "Open world"
			_dialog.filters = PackedStringArray(["*.world.json ; World manifests"])
			_dialog.current_file = _world_path.get_file() if not _world_path.is_empty() else "world.world.json"
			if not _world_path.is_empty():
				_dialog.current_dir = ProjectSettings.globalize_path(_world_path.get_base_dir())
		"save":
			_dialog.title = "Save terrain and settings"
			_dialog.filters = PackedStringArray(["*.terrain.json ; Terrain maps"])
			_dialog.current_file = "terrain-" + _terrain.map_seed.validate_filename().left(40) + ".terrain.json"
		"load":
			_dialog.title = "Load terrain"
			_dialog.filters = PackedStringArray(["*.terrain.json ; Terrain maps", "*.json ; JSON files"])
		"image":
			_dialog.title = "Import grayscale heightmap"
			_dialog.filters = PackedStringArray(["*.png ; PNG images", "*.exr ; EXR images", "*.jpg,*.jpeg ; JPEG images", "*.webp ; WebP images"])
		"export":
			_dialog.title = "Export heightmap (8-bit PNG)"
			_dialog.filters = PackedStringArray(["*.png ; PNG images"])
			_dialog.current_file = "heightmap.png"
	_dialog.popup_centered()


func _file_selected(path: String) -> void:
	match _dialog_action:
		"save_world":
			if save_world(path).is_empty() and _resume_after_save:
				_resume_pending_action()
		"load_world":
			request_action(func(): load_world(path))
		"save":
			var error: String = Document.save_file(path, _terrain)
			if error.is_empty():
				_terrain_path = path
			_status.text = "Saved " + path.get_file() if error.is_empty() else error
		"load":
			request_action(func(): load_terrain(path))
		"image":
			var image := Image.new()
			if image.load(path) != OK or image.is_empty():
				_status.text = "Could not open that heightmap image."
				return
			_pending_image = ImageTexture.create_from_image(image)
			_image_path = path
			_image_size = image.get_size()
			var picker := _controls["terrain_template"] as OptionButton
			picker.set_item_disabled(_custom_index, false)
			picker.select(_custom_index)
			_update_description()
			_settings_changed()
		"export":
			var image: Image = _terrain.heightmap_image()
			image.convert(Image.FORMAT_L8)
			_status.text = "Exported " + path.get_file() if image.save_png(path) == OK else "Heightmap export failed."


func load_terrain(path: String) -> String:
	var result: Dictionary = Document.load_file(path)
	if not result.ok:
		_status.text = result.error
		return result.error
	var error: String = Document.apply(_terrain, result.document)
	if error.is_empty():
		_terrain_path = path
		_world_path = ""
		mark_dirty()
		_sync_from_terrain()
		get_parent().get_parent().get_node("CameraRig")._reset_view()
		_status.text = "Loaded " + path.get_file() + "\nSaved terrain samples restored exactly."
	else:
		_status.text = error
	return error


func _build_cell_inspector() -> void:
	var panel := PanelContainer.new()
	panel.name = "CellInspector"
	_cell_panel = panel
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.offset_left = 14
	panel.offset_right = 240
	panel.offset_top = 420
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -470
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var background := StyleBoxFlat.new()
	background.bg_color = Color("14212ce8")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		background.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", background)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_cell_label = Label.new()
	_cell_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cell_label.text = "CELL DATA\nClick the map to inspect its terrain."
	_cell_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_cell_label)
	add_child(panel)
	_terrain.climate_changed.connect(_refresh_selected_cell)
	_terrain.terrain_regenerated.connect(_reset_cell_inspector)
	_reset_cell_inspector()


func _open_ground_palette() -> void:
	_select_layer("ground")
	if _material_panel == null:
		_material_panel = MaterialPanel.new()
		_material_panel.visible = false
		add_child(_material_panel)
	_material_panel.configure(_terrain, self)
	_material_panel.popup_centered()


func _reset_cell_inspector() -> void:
	_selected_cell = -1
	_selected_point = Vector2.INF
	_cell_label.text = "CELL DATA\nClick the map to inspect its terrain." if _terrain.graph != null else "LEGACY TERRAIN\nGenerate to create cell data."
	_cell_panel.anchor_bottom = 0.0
	_cell_panel.offset_bottom = 520



func _unhandled_input(event: InputEvent) -> void:
	if _brush != null and _brush.handle_input(event):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera: Camera3D = get_parent().get_parent().get_node("CameraRig/Camera3D")
		var info: Dictionary = _terrain.pick_cell(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
		if not info.is_empty():
			_selected_cell = info.id
			_selected_point = info.inspected_position
			_show_cell_info(info)


func _refresh_selected_cell() -> void:
	if _selected_cell >= 0:
		var info: Dictionary = _terrain.point_info(_selected_point) if _selected_point.is_finite() else _terrain.cell_info(_selected_cell)
		if not info.is_empty():
			_show_cell_info(info)


func _show_cell_info(info: Dictionary) -> void:
	if _terrain.heightmap_only:
		var point: Vector2 = info.get("inspected_position", info.position)
		var h: float = (_terrain.base_surface_height(point / _terrain.map_size) / _terrain.relief_scale() - _terrain.height_offset) / _terrain.elevation + (0.2 if _terrain.generator_version >= 3 else 0.0)
		_cell_label.text = "HEIGHTMAP SAMPLE\nX %.2f · Y %.2f\nHeight %.3f / 1.0\n%s" % [point.x, point.y, h, "Below sea datum" if h < 0.2 else "Land"]
		return
	_cell_panel.anchor_bottom = 1.0
	_cell_panel.offset_bottom = -14
	_cell_label.text = "CELL %d · %s\nX %.2f   Y %.2f\nHeight %d / 100 · sea datum 20\n%d neighbors\nArea %.2f map units²" % [info.id, info.get("surface_kind", "Land" if info.land else "Water"), info.position.x, info.position.y, info.height, info.neighbor_count, info.area]
	if info.has("inspected_position"):
		_cell_label.text += "\nClicked at %.2f, %.2f · %s" % [info.inspected_position.x, info.inspected_position.y, info.surface_kind]
		if info.cell_biome != info.biome or info.cell_surface_kind != info.surface_kind:
			_cell_label.text += "\nCell classification: %s · %s" % [info.cell_surface_kind, info.cell_biome]
	if info.has("painted_ground"):
		_cell_label.text += "\nPaint layer: %s · %s" % [info.painted_ground, info.painted_texture]
	if info.has("basin_id"):
		if info.basin_id >= 0:
			var basin: Dictionary = _terrain.hydrology.basins[info.basin_id]
			var destinations := {"ocean": "ocean", "map_edge": "map edge", "closed_lake": "closed lake", "dry_depression": "dry depression"}
			_cell_label.text += "\nBasin #%d · drains to %s" % [info.basin_id, destinations[basin.kind]]
		if info.river_id >= 0:
			_cell_label.text += "\nRiver reach #%d · flow %.1f×" % [info.river_id, info.flow_strength]
		if info.lake_id >= 0:
			_cell_label.text += "\nLake basin #%d · spill level %.1f / 100\n%s" % [info.lake_id, info.lake_level, ("Outlet: cell %d" % info.lake_outlet) if info.lake_outlet >= 0 else ("Closed lake: inflow lost to evaporation" if info.lake_active else "Dry basin: no rainfall runoff")]

			if info.lake_active:
				_cell_label.text += "\nLake depth: %.1f height units" % info.water_depth
	if info.has("feature_id"):
		var names := {"landmass": "Large landmass", "island": "Island", "open_water": "Open water", "inland_water": "Inland water (lake candidate)"}
		var distance: String = "No coastline" if info.coast_distance < 0.0 else "About %.1f map units from coast" % info.coast_distance
		_cell_label.text += "\n%s #%d\n%s · %d cells\nFeature area: %.1f map units²\n%s\n%s" % [names[info.feature_kind], info.feature_id, "Touches map border" if info.touches_border else "Enclosed within map", info.feature_cells, info.feature_area, "Coastal cell" if info.coastal else "Away from coast", distance]
		if not info.land:
			_cell_label.text += "\nHeight below sea datum: %d units" % info.depth
	if info.has("temperature"):
		_cell_label.text += "\nBiome at point: %s\nLatitude: %+.1f°\nTemperature: %.1f°C\nRainfall: %.0f mm/yr (est.)\nWind travels: %s" % [info.biome, info.latitude, info.temperature, info.rainfall, _wind_name(info.wind)]
		if info.has("canopy"):
			_cell_label.text += "\nPotential tree cover: %.0f%% · nearby water: %.0f%%" % [info.canopy * 100.0, info.water_support * 100.0]
		if info.get("water_support", 0.0) > 0.05 and info.get("surface_kind", "Land") == "Land":
			_cell_label.text += "\nWater-fed margin: ground cover blends locally"
		if info.has("tree_count"):
			_cell_label.text += "\nPlaced trees in this cell: %d" % info.tree_count




func _wind_name(wind: Vector2) -> String:
	var bearing: float = fposmod(rad_to_deg(atan2(wind.x, -wind.y)), 360.0)
	return ["North", "North-east", "East", "South-east", "South", "South-west", "West", "North-west"][roundi(bearing / 45.0) % 8]


func _build_shell() -> void:
	var scroll := _form.get_parent()
	scroll.remove_child(_form)
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(host)
	host.add_child(_form)
	_context_host = _form
	_toolbar = HBoxContainer.new()
	_toolbar.name = "Toolbar"
	_toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toolbar.offset_left = 14
	_toolbar.offset_right = -14
	_toolbar.offset_top = 10
	_toolbar.offset_bottom = 50
	add_child(_toolbar)
	_button("Save world…", _save_current_world, _toolbar, "SaveWorld")
	_button("Save as…", func(): _show_dialog("save_world"), _toolbar, "SaveWorldAs")
	_button("Open world…", func(): _show_dialog("load_world"), _toolbar, "OpenWorld")
	_button("View settings", func(): _select_layer("view"), _toolbar)
	_button("Full map", func(): _camera_rig._reset_view(), _toolbar)
	if _terrain.heightmap_only:
		_button("Play map", play_map, _toolbar, "PlayMap")
	var stack := VBoxContainer.new()
	stack.name = "LayerStack"
	stack.position = Vector2(14, 60)
	stack.custom_minimum_size.x = 226
	add_child(stack)
	var title := Label.new()
	title.text = "MAP LAYERS"
	stack.add_child(title)
	for layer in layers:
		var row := HBoxContainer.new()
		stack.add_child(row)
		_button(layer.title, func(): _select_layer(layer.id), row)
		var selector := row.get_child(0) as Button
		selector.toggle_mode = true
		_layer_selectors[layer.id] = selector
		var eye := CheckBox.new()
		eye.text = "V"
		eye.tooltip_text = "Show layer (heightmap is the base world)"
		eye.button_pressed = layer.visible
		eye.toggled.connect(func(value: bool): layer.visible = value; _apply_layer_visibility(); mark_dirty())
		row.add_child(eye)
		var lock := CheckBox.new()
		lock.text = "L"
		lock.tooltip_text = "Protect this layer from editor changes"
		lock.toggled.connect(func(value: bool): layer.locked = value; _stop_brush(); _update_dependency_status(); mark_dirty())
		row.add_child(lock)
		_layer_buttons[layer.id] = [eye, lock]
		if _terrain.heightmap_only and layer.id != "heightmap":
			layer.visible = false
			eye.set_pressed_no_signal(false)
			eye.disabled = true
			lock.disabled = true
			selector.disabled = true
			selector.tooltip_text = "Disabled while we focus on the heightmap."

	_dependency_status = Label.new()
	_dependency_status.custom_minimum_size.x = 226
	_dependency_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dependency_status.add_theme_font_size_override("font_size", 12)
	stack.add_child(_dependency_status)
	# The central region stays transparent to the existing 3D camera and picking.
	var viewport_label := Label.new()
	viewport_label.name = "MapViewport"
	viewport_label.text = "WORLD VIEW · Wheel to zoom · WASD to move"
	viewport_label.position = Vector2(256, 65)
	viewport_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_label)

func _context(key: String) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context_host.get_parent().add_child(box)
	_contexts[key] = box
	_form = box

func _select_layer(key: String) -> void:
	if _terrain.heightmap_only and key not in ["heightmap", "view"]:
		key = "heightmap"
	if selected_layer != key:
		mark_dirty()
	selected_layer = key
	for id in _layer_selectors:
		_layer_selectors[id].set_pressed_no_signal(id == key)
	for id in _contexts:
		_contexts[id].visible = id == key
	_update_dependency_status()
	_stop_brush()

func _stop_brush() -> void:
	if _brush != null:
		_brush.painting = false
		_brush.enabled.button_pressed = false

func can_edit(key: String) -> bool:
	if _terrain.heightmap_only and key != "heightmap":
		return false
	for layer in layers:
		if layer.id == key:
			return not layer.locked and layer.visible
	return false

func regeneration_error(key: String) -> String:
	if _terrain.heightmap_only:
		return "" if key == "heightmap" and can_edit(key) else "Heightmap is hidden or locked. Other layers are disabled for now."
	if not layer_visible(key):
		return "Show the layer before editing it."
	return LayerGraph.lock_reason(layers, key)

func _update_dependency_status() -> void:
	if _dependency_status == null:
		return
	if _terrain.heightmap_only:
		_dependency_status.text = "HEIGHTMAP ONLY\nTrees, biomes, rivers and lakes are disabled."
		return
	var affected := LayerGraph.affected(layers, selected_layer)
	var names: PackedStringArray = []
	for layer in layers:
		if layer.id in affected:
			names.append(layer.title)
	_dependency_status.text = "Changes affect: " + ", ".join(names) if not names.is_empty() else "Camera settings do not change map data."
	var reason := LayerGraph.lock_reason(layers, selected_layer)
	if not reason.is_empty() and not affected.is_empty():
		_dependency_status.text += "\n" + reason


func _apply_layer_visibility() -> void:
	if _terrain.heightmap_only:
		_terrain.visible = layers[0].visible
		for layer in layers:
			if layer.id != "heightmap":
				layer.visible = false
				_layer_buttons[layer.id][0].set_pressed_no_signal(false)
		return
	for layer in layers:
		match layer.id:
			"heightmap": _terrain.visible = layer.visible
			"trees":
				if _terrain.vegetation_view != null:
					_terrain.vegetation_view.editor_visible = layer.visible
					_terrain.vegetation_view._update_visibility()
			"ground":
				if _terrain.paint_layer != null:
					_terrain.paint_layer.editor_visible = layer.visible
					_terrain.update_painted_surface()
			"climate":
				if not layer.visible:
					_terrain.set_climate_view(0)
			"rivers":
				if _terrain.hydrology_view != null:
					_terrain.hydrology_view.editor_visible = layer.visible
					_terrain.hydrology_view._update_visibility()
	_stop_brush()

func load_world(path: String) -> String:
	var result: Dictionary = Manifest.load_file(path)
	if not result.error.is_empty():
		_status.text = result.error
		return result.error
	var data: Dictionary = result.document
	var terrain_path: String = data.terrain
	if not terrain_path.is_absolute_path():
		terrain_path = path.get_base_dir().path_join(terrain_path)
	var error := load_terrain(terrain_path)
	if not error.is_empty():
		return error
	for entry in data.layers:
		for layer in layers:
			if layer.id == entry.id:
				layer.visible = entry.visible
				layer.locked = entry.locked
				_layer_buttons[layer.id][0].set_pressed_no_signal(layer.visible)
				_layer_buttons[layer.id][1].set_pressed_no_signal(layer.locked)
	_select_layer(data.selected_layer)
	_apply_layer_visibility()
	_world_path = path
	_set_clean()
	return ""

func layer_visible(key: String) -> bool:
	for layer in layers:
		if layer.id == key:
			return layer.visible
	return false

func save_world(path: String) -> String:
	_stop_brush()
	var result := WorldProject.save_file(path, _terrain, layers, selected_layer if selected_layer != "view" else "heightmap")
	if not result.error.is_empty():
		_status.text = result.error
		_cancel_pending_action()
		return result.error
	_world_path = path
	_terrain_path = result.terrain_path
	_set_clean()
	_status.text = "Saved current terrain and layers: " + path.get_file()
	return ""

func _save_current_world() -> void:
	if _world_path.is_empty():
		_show_dialog("save_world")
	else:
		if save_world(_world_path).is_empty() and _resume_after_save:
			_resume_pending_action()

func _setup_document_tracking() -> void:
	_world_status = Label.new()
	_world_status.name = "WorldStatus"
	_world_status.position = Vector2(256, 87)
	_world_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world_status)
	_unsaved_dialog = ConfirmationDialog.new()
	_unsaved_dialog.title = "Unsaved world changes"
	_unsaved_dialog.dialog_text = "Save this world before continuing?"
	_unsaved_dialog.ok_button_text = "Discard changes"
	_unsaved_dialog.add_button("Save world…", false, "save")
	_unsaved_dialog.confirmed.connect(_resume_pending_action)
	_unsaved_dialog.canceled.connect(_cancel_pending_action)
	_unsaved_dialog.custom_action.connect(func(action: String):
		if action == "save":
			_unsaved_dialog.hide()
			_resume_after_save = true
			_save_current_world())
	add_child(_unsaved_dialog)
	_dialog.canceled.connect(_cancel_pending_action)
	_terrain.terrain_regenerated.connect(mark_dirty)
	_terrain.climate_changed.connect(mark_dirty)
	_terrain.vegetation_changed.connect(mark_dirty)
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_request_app_close)
	_tracking_changes = true
	_update_world_status()

func mark_dirty() -> void:
	if not _tracking_changes:
		return
	dirty = true
	_update_world_status()

func _set_clean() -> void:
	dirty = false
	_update_world_status()

func _update_world_status() -> void:
	if _world_status != null:
		_world_status.text = ("Unsaved changes" if dirty else "Saved") + (" · " + _world_path.get_file() if not _world_path.is_empty() else " · New world")

func request_action(action: Callable) -> void:
	if dirty:
		_pending_action = action
		_unsaved_dialog.popup_centered()
	else:
		action.call()

func _resume_pending_action() -> void:
	var action := _pending_action
	_cancel_pending_action()
	if action.is_valid():
		action.call()

func _cancel_pending_action() -> void:
	_pending_action = Callable()
	_resume_after_save = false


func play_map() -> void:
	if _gameplay_map != null:
		return
	var document: Dictionary = Document.capture(_terrain)
	var error := Document.validate(document)
	if not error.is_empty():
		_status.text = error
		return
	_stop_brush()
	var gameplay := load("res://scenes/gameplay_map.tscn") as PackedScene
	_gameplay_map = gameplay.instantiate()
	_gameplay_map.get_node("Terrain").startup_document = document
	_gameplay_map.return_requested.connect(_return_from_map)
	var editor_world := get_parent().get_parent() as Node3D
	_editor_process_mode = editor_world.process_mode
	editor_world.process_mode = Node.PROCESS_MODE_DISABLED
	editor_world.visible = false
	get_parent().visible = false
	get_tree().root.add_child(_gameplay_map)

func _return_from_map() -> void:
	if _gameplay_map == null:
		return
	_gameplay_map.queue_free()
	_gameplay_map = null
	var editor_world := get_parent().get_parent() as Node3D
	editor_world.visible = true
	editor_world.process_mode = _editor_process_mode
	get_parent().visible = true
	_camera_rig._camera.make_current()

func _request_app_close() -> void:
	_return_from_map()
	request_action(func(): get_tree().quit())
