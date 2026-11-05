extends Control
## Runtime controls stage generation settings; save/load operate on the visible map.

const WorldProject = preload("res://scripts/storage/world_project.gd")
const LayerGraph = preload("res://scripts/domain/map_layer_graph.gd")
const ForestPanel = preload("res://scripts/ui/forest_panel.gd")
const RegionalPanel = preload("res://scripts/ui/regional_panel.gd")
var _regional_panel: RefCounted
var _forest_panel: RefCounted
const PaintBrush = preload("res://scripts/ui/map_paint_brush.gd")
var _paint_brush: Node
const ProvinceBorderBrush = preload("res://scripts/ui/province_border_brush.gd")
var _border_controls: Dictionary = {}
var _province_brush: Node
var _ocean_count: SpinBox
var _ocean_style: OptionButton
var _coastal_reach: SpinBox
const WorldProvinces = preload("res://scripts/domain/world_provinces.gd")
const TerrainSurface = preload("res://scripts/domain/terrain_surface.gd")
const WaterLayer = preload("res://scripts/domain/terrain_water_layer.gd")
const Manifest = preload("res://scripts/storage/world_manifest.gd")
var layers: Array = Manifest.default_layers()
var selected_layer := "heightmap"
var _terrain_path := ""
var _province_count: SpinBox
var _province_status: Label
var _province_nation: OptionButton
var _province_name: LineEdit
var _province_selected := 0
var _province_thread: Thread
var _province_busy := false
var _province_generate: Button
var _surface_status: Label
var _surface_controls: Dictionary = {}
var _surface_thread: Thread
var _surface_busy := false
var _surface_generate: Button
var _water_controls: Dictionary = {}
var _water_status: Label
var _water_generate: Button
var _water_thread: Thread
var _water_job_serial := 0
var _water_busy := false
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
var _toolbar: HBoxContainer

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
var _custom_index: int = -1
var _image_size := Vector2i.ZERO


func _ready() -> void:
	_terrain = get_parent().get_parent().get_node("Terrain")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera_rig = get_parent().get_parent().get_node("CameraRig")
	_build_interface()
	_camera_rig.zoom_changed.connect(_update_zoom_status)
	_sync_from_terrain()
	_update_zoom_status()
	_terrain.terrain_regenerated.connect(_update_preview)
	_update_preview()
	_terrain.terrain_regenerated.connect(_apply_layer_visibility)
	_build_cell_inspector()
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
		_number("Output resolution (px)", "heightmap_resolution", 256, 2050, 1)
		_controls["heightmap_resolution"].update_on_text_changed = true
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
	_context("paint")
	_paint_brush = PaintBrush.new()
	add_child(_paint_brush)
	_paint_brush.configure(self)
	_context("trees")
	_forest_panel = ForestPanel.new()
	_forest_panel.configure(self)
	_context("regions")
	_regional_panel = RegionalPanel.new()
	_regional_panel.configure(self)
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
	if _terrain.heightmap_only:
		_build_water_controls()
	else:
		_label("Generated from height and climate. Independent river authoring is planned.").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context("surface")
	_label("Terrain surface", 22)
	if _terrain.heightmap_only:
		_build_surface_controls()
	else:
		_label("Available in the focused terrain workspace.")
	_context("provinces")
	_label("Provinces", 22)
	if _terrain.heightmap_only:
		_build_province_controls()
	else:
		_label("Available in the focused terrain workspace.")
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
	_paint_brush.sync_textures()
	_regional_panel.sync()
	_forest_panel.sync()
	_sync_border_appearance_controls()
	if _terrain.heightmap_only:
		if _province_count != null and _terrain.province_layer != null:
			_province_count.set_value_no_signal(_terrain.province_layer.requested_count)
			_ocean_count.set_value_no_signal(_terrain.province_layer.requested_oceans)
			_ocean_style.select(1 if _terrain.province_layer.ocean_style == "open" else 0)
			_coastal_reach.set_value_no_signal(_terrain.province_layer.coastal_reach)
			_select_province(0)
		_controls["coast_detail"].set_value_no_signal(_terrain.coast_detail)
		_controls["mountain_detail"].set_value_no_signal(_terrain.mountain_detail)
		_controls["heightmap_resolution"].set_value_no_signal(_terrain.resolution + 1)
		_sync_water_controls()
		if _surface_status != null:
			for key in _surface_controls:
				_surface_controls[key].set_value_no_signal(_terrain.terrain_surface.settings[key] if _terrain.terrain_surface != null else TerrainSurface.DEFAULTS[key])
			_update_surface_status()
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
		_terrain.resolution = int(_controls["heightmap_resolution"].value) - 1
	_terrain.island_enabled = (_controls["island_enabled"] as CheckBox).button_pressed
	_terrain.elevation = _controls["elevation"].value
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
		"export_surface":
			_dialog.title = "Export terrain surface heightmap"
			_dialog.filters = PackedStringArray(["*.png ; PNG images"])
			_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			_dialog.current_file = "terrain-surface.png"
		"export_water":
			_dialog.title = "Export rivers / lakes (transparent PNG)"
			_dialog.filters = PackedStringArray(["*.png ; PNG images"])
			_dialog.current_file = "rivers-lakes.png"
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
		"export_surface":
			if not _terrain.terrain_surface_current():
				_surface_status.text = "Build the current terrain surface before exporting."
			else:
				_surface_status.text = "Terrain surface exported." if _terrain.terrain_surface.export_image().save_png(path) == OK else "Could not export terrain surface."
		"export_water":
			if not _terrain.water_layer_current():
				_water_status.text = "Generate water for the current heightmap before exporting."
			else:
				_water_status.text = "Water layer exported." if _terrain.water_layer.export_image().save_png(path) == OK else "Could not export the water layer."
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
		_water_job_serial += 1
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
	panel.offset_top = 455
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
	_terrain.terrain_regenerated.connect(_reset_cell_inspector)
	_reset_cell_inspector()


func _reset_cell_inspector() -> void:
	_selected_cell = -1
	_selected_point = Vector2.INF
	_cell_label.text = "CELL DATA\nClick the map to inspect its terrain." if _terrain.graph != null else "LEGACY TERRAIN\nGenerate to create cell data."
	_cell_panel.anchor_bottom = 0.0
	_cell_panel.offset_bottom = 555



func _unhandled_input(event: InputEvent) -> void:
	if _regional_panel != null and _regional_panel.handle_input(event): return
	if _paint_brush != null and _paint_brush.handle_input(event): return
	if _province_brush != null and _province_brush.handle_input(event):
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
		if _terrain.province_layer_current():
			_select_province(_terrain.province_layer.id_at(point / _terrain.map_size))
			if _terrain.province_layer.is_impassable(point / _terrain.map_size): _cell_label.text += "\nImpassable land (unassigned)"
			if _province_selected > 0:
				var record: Dictionary = _terrain.province_layer.records[_province_selected - 1]
				var kind_text := "Land province" if record.kind == "land" else ("Inland-water province" if record.kind == "inland_water" else "Coastal sea province")
				_cell_label.text += "\n%s · %s (ID %d)\n%d map pixels, %d neighbors" % [record.name, kind_text, record.id, record.pixels, record.neighbors.size()]
				if not record.neighbors.is_empty():
					var names: Array[String] = []
					for neighbor_id in record.neighbors:
						if neighbor_id > 0 and neighbor_id <= _terrain.province_layer.records.size(): names.append(_terrain.province_layer.records[neighbor_id - 1].name)
					_cell_label.text += "\nNeighbors: " + ", ".join(names.slice(0, 8))
				var crossing_count := 0
				var strait_count := 0
				for connection in _terrain.province_layer.connections:
					if connection.a == record.id or connection.b == record.id:
						if connection.type == "river_crossing": crossing_count += 1
						elif connection.type == "strait": strait_count += 1
				_cell_label.text += "\nConnections: %d river crossings · %d straits" % [crossing_count, strait_count]
				if record.kind == "land" and record.parts > 1: _cell_label.text += "\n%d land parts" % record.parts
				_cell_panel.offset_bottom = 620
			else:
				var sample := Vector2i((point / _terrain.map_size * Vector2(_terrain.province_layer.size)).floor()).clamp(Vector2i.ZERO, _terrain.province_layer.size - Vector2i.ONE)
				var sample_index: int = sample.y * _terrain.province_layer.size.x + sample.x
				var water_kind := "Unassigned coastal sea" if _terrain.province_layer.sea_mask.size() == _terrain.province_layer.ids.size() and _terrain.province_layer.sea_mask[sample_index] != 0 else "Unassigned water"
				if _terrain.province_layer.is_impassable(point / _terrain.map_size): water_kind = "Unassigned impassable land"
				_cell_label.text += "\n" + water_kind
		return


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
	_button("Terrain3D test", func(): OS.create_process(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "res://scenes/terrain3d_trial.tscn"]), _toolbar, "Terrain3DTest")
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
		lock.tooltip_text = "Lock tree settings; forests still follow regenerated terrain." if layer.id == "trees" else "Protect this layer from editor changes"
		lock.toggled.connect(func(value: bool): layer.locked = value; _stop_brush(); _update_dependency_status(); mark_dirty())
		row.add_child(lock)
		_layer_buttons[layer.id] = [eye, lock]
		if _terrain.heightmap_only and layer.id not in ["heightmap", "rivers", "surface", "provinces", "paint", "trees"]:
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
	if _terrain.heightmap_only and key not in ["heightmap", "rivers", "surface", "provinces", "paint", "trees", "view"]:
		key = "heightmap"
	if selected_layer != key:
		mark_dirty()
	selected_layer = key
	if key in ["paint", "rivers", "surface", "provinces", "trees"] and _terrain.heightmap_only:
		find_child("RawHeightView", true, false).button_pressed = false
	for id in _layer_selectors:
		_layer_selectors[id].set_pressed_no_signal(id == key)
	for id in _contexts:
		_contexts[id].visible = id == key
	_update_dependency_status()
	_stop_brush()
	if key == "trees": _forest_panel.update_status()

func _show_regions() -> void:
	_select_layer("paint")
	_contexts.paint.visible = false
	_contexts.regions.visible = true
	_regional_panel.update_preview()

func _stop_brush() -> void:
	if _regional_panel != null: _regional_panel.stop()
	if _paint_brush != null:
		_paint_brush.cancel()
		_paint_brush.enabled.button_pressed = false
	if _province_brush != null:
		_province_brush.cancel()
		_province_brush.enabled.button_pressed = false

func can_edit(key: String) -> bool:
	if _terrain.heightmap_only and key not in ["heightmap", "rivers", "surface", "provinces", "paint", "trees"]:
		return false
	for layer in layers:
		if layer.id == key:
			return not layer.locked and layer.visible
	return false

func regeneration_error(key: String) -> String:
	if _terrain.heightmap_only:
		if key not in ["heightmap", "rivers", "surface", "provinces", "paint", "trees"] or not can_edit(key):
			return "Show and unlock the selected layer before generating."
		if key in ["heightmap", "rivers", "surface"]:
			for layer in layers:
				if layer.id == "provinces" and layer.locked:
					return "Unlock Provinces before changing its source maps."
		if key in ["heightmap", "rivers"]:
			for layer in layers:
				if layer.id == "surface" and layer.locked:
					return "Unlock Terrain surface before changing its source maps."
		if key == "heightmap":
			for layer in layers:
				if layer.id == "rivers" and layer.locked:
					return "Unlock Rivers / lakes before changing its source heightmap."
		return ""
	if not layer_visible(key):
		return "Show the layer before editing it."
	return LayerGraph.lock_reason(layers, key)

func _update_dependency_status() -> void:
	if _dependency_status == null:
		return
	if _terrain.heightmap_only:
		_dependency_status.text = "TERRAIN WORKFLOW\n1. Generate heightmap\n2. Generate rivers / lakes\n3. Build terrain surface\n4. Generate provinces"
		if _terrain.water_layer != null and not _terrain.water_layer_current():
			_dependency_status.text += "\nWater needs regeneration."
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
	_terrain.tree_layer_visible = layer_visible("trees")
	_terrain.paint_layer_visible = layer_visible("paint")
	_terrain.set_height_layer_visible(layer_visible("heightmap"))
	_terrain.set_province_layer_visible(layer_visible("provinces"))
	_terrain.set_surface_layer_visible(layer_visible("surface"))
	_terrain.set_water_layer_visible(layer_visible("rivers"))
	_update_province_status()
	_update_surface_status()
	_update_water_status()
	if _forest_panel != null: _forest_panel.update_status()

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
	_terrain.presentation_changed.connect(_update_world_status)
	_terrain.terrain_regenerated.connect(mark_dirty)
	_terrain.province_layer_changed.connect(mark_dirty)
	_terrain.province_layer_changed.connect(_apply_layer_visibility)
	_terrain.terrain_surface_changed.connect(mark_dirty)
	_terrain.terrain_surface_changed.connect(_apply_layer_visibility)
	_terrain.water_layer_changed.connect(mark_dirty)
	_terrain.water_layer_changed.connect(_apply_layer_visibility)
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
		if _terrain.map_renderer != null and _terrain.map_renderer.display_pending(): _world_status.text += " · Updating terrain view…"

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
	if _water_busy or _surface_busy or _province_busy:
		_status.text = "Wait for map generation before opening Play map."
		return
	if _terrain.heightmap_only and _terrain.water_layer != null and not _terrain.terrain_surface_current():
		_select_layer("surface")
		_surface_status.text = "Build the terrain surface for the current source maps before Play map."
		return
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
	if _regional_panel.active(): _regional_panel.update_preview()

func _request_app_close() -> void:
	_return_from_map()
	request_action(func(): get_tree().quit())


func _build_water_controls() -> void:
	_label("Generate this layer after the heightmap. Then build Terrain surface to shape the ground beneath this water.").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label("Drainage detail")
	var routing := OptionButton.new()
	for samples in [257, 513, 1025]:
		routing.add_item(str(samples) + " routing samples")
		routing.set_item_metadata(routing.item_count - 1, samples)
	routing.select(1)
	routing.tooltip_text = "Higher drainage detail follows smaller valleys. The final water image always matches the heightmap output resolution."
	_form.add_child(routing)
	_water_controls["routing_resolution"] = routing
	routing.item_selected.connect(func(_index: int): _water_settings_changed())
	_water_number("River density", "density", 0.25, 4, 0.25, "Higher values include smaller tributaries.")
	_water_number("River width", "width", 0.5, 8, 0.25, "Choose headwater width. Rivers widen downstream with accumulated flow and scale with output resolution.")
	_water_number("Minimum lake depth", "lake_depth", 0.002, 0.1, 0.002, "Minimum depression depth in normalized height units; larger values filter shallow pools.")
	_water_number("Minimum lake area (%)", "lake_area", 0.001, 1, 0.001, "Minimum lake footprint as a percentage of the drainage map, to filter small puddles.")
	_button("Generate rivers / lakes", generate_water_layer, null, "GenerateWater")
	_water_generate = _form.get_child(_form.get_child_count() - 1)
	_button("Export water PNG…", func(): _show_dialog("export_water"), null, "ExportWater")
	_water_status = _label("Not generated. Create a heightmap, then generate this layer.", 13)
	_water_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _water_number(title: String, key: String, minimum: float, maximum: float, step: float, hint: String) -> void:
	var row := _row(title)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = WaterLayer.DEFAULTS[key]
	spin.tooltip_text = hint
	spin.custom_minimum_size.x = 110
	row.add_child(spin)
	_water_controls[key] = spin
	spin.value_changed.connect(func(_value: float): _water_settings_changed())
func _sync_water_controls() -> void:
	if _water_status == null:
		return
	var choices: Dictionary = _terrain.water_layer.settings if _terrain.water_layer != null else WaterLayer.DEFAULTS
	for key in _water_controls:
		if key == "routing_resolution":
			var picker: OptionButton = _water_controls[key]
			for i in range(picker.item_count):
				if picker.get_item_metadata(i) == int(choices[key]):
					picker.select(i)
		else:
			_water_controls[key].set_value_no_signal(choices[key])
	_update_water_status()

func _update_water_status() -> void:
	if _water_status == null or _water_busy:
		return
	_update_dependency_status()
	var selector: Button = _layer_selectors["rivers"]
	selector.text = "Rivers / lakes *" if _terrain.water_layer != null and not _terrain.water_layer_current() else "Rivers / lakes"
	if _terrain.water_layer == null:
		_water_status.text = "Not generated. Generate rivers / lakes for the current heightmap."
	elif not _terrain.water_layer_current():
		_water_status.text = "Heightmap changed. The previous water layer is retained but hidden. Generate it again for this terrain."
	else:
		var layer = _terrain.water_layer
		_water_status.text = "%d river sections · %d lakes\n%d × %d water image" % [layer.river_reaches, layer.lake_count, layer.mask_size.x, layer.mask_size.y]

func generate_water_layer() -> void:
	if _water_busy:
		return
	var error := regeneration_error("rivers")
	if not error.is_empty():
		_water_status.text = error
		return
	var serial := _water_job_serial
	var source: PackedFloat32Array = _terrain.map_renderer.normalized_heights.duplicate()
	var size: Vector2i = _terrain.sample_size()
	var source_hash: String = _terrain.water_source_hash
	_water_busy = true
	_water_generate.disabled = true
	for control in _water_controls.values():
		if control is SpinBox:
			control.apply()
	await get_tree().process_frame
	if serial != _water_job_serial or source_hash != _terrain.water_source_hash or not regeneration_error("rivers").is_empty():
		_water_busy = false
		_water_generate.disabled = false
		_update_water_status()
		_water_status.text = "The terrain or document changed. Generate water again."
		return
	var choices: Dictionary = {}
	for key in _water_controls:
		var control = _water_controls[key]
		choices[key] = control.get_item_metadata(control.selected) if control is OptionButton else control.value
	_water_thread = Thread.new()
	_water_status.text = "Routing drainage and drawing the water layer…"
	_water_generate.disabled = true
	var started := _water_thread.start(func():
		var layer := WaterLayer.new()
		var result := layer.generate(source, size, source_hash, choices)
		return {"error": result, "layer": layer})
	if started != OK:
		_water_thread = null
		_water_busy = false
		_water_generate.disabled = false
		_water_status.text = "Could not start water generation."
		return
	while _water_thread.is_alive():
		await get_tree().process_frame
	var result: Dictionary = _water_thread.wait_to_finish()
	_water_thread = null
	_water_busy = false
	_water_generate.disabled = false
	_update_water_status()
	if serial != _water_job_serial:
		_water_status.text = "The open document changed. Generate water again."
		return
	if not result.error.is_empty():
		_water_status.text = result.error
		return
	if not regeneration_error("rivers").is_empty():
		_water_status.text = regeneration_error("rivers")
		return
	error = _terrain.install_water_layer(result.layer)
	if not error.is_empty():
		_water_status.text = error
	else:
		_update_water_status()

func _exit_tree() -> void:
	if _province_thread != null and _province_thread.is_started():
		_province_thread.wait_to_finish()
	if _surface_thread != null and _surface_thread.is_started():
		_surface_thread.wait_to_finish()
	if _water_thread != null and _water_thread.is_started():
		_water_thread.wait_to_finish()

func _water_settings_changed() -> void:
	if _water_status != null and not _water_busy:
		_water_status.text = "Settings changed. Generate rivers / lakes to apply them."

func _build_surface_controls() -> void:
	_label("Step 3: shape riverbeds, lake basins and banks. Your source heightmap and water records are preserved.").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for key in TerrainSurface.DEFAULTS:
		var row := HBoxContainer.new()
		var title := Label.new()
		title.text = {"river_depth": "Riverbed depth", "lake_depth": "Lake bed depth", "bank_width": "Bank width"}[key]
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var spin := SpinBox.new()
		spin.min_value = 1 if key == "bank_width" else 0.001
		spin.max_value = 12 if key == "bank_width" else 0.05
		spin.step = 0.5 if key == "bank_width" else 0.001
		spin.value = TerrainSurface.DEFAULTS[key]
		spin.value_changed.connect(func(_value: float):
			if _surface_status != null and not _surface_busy:
				_surface_status.text = "Settings changed. Build terrain surface to apply them.")
		row.add_child(spin)
		_form.add_child(row)
		_surface_controls[key] = spin
	_button("Build terrain surface", build_terrain_surface, null, "BuildSurface")
	_surface_generate = _form.get_child(_form.get_child_count() - 1)
	_button("Export surface PNG…", func(): _show_dialog("export_surface"), null, "ExportSurface")
	_surface_status = _label("Generate the two source maps first.", 13)
	_surface_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _update_surface_status() -> void:
	if _surface_status == null or _surface_busy:
		return
	var current: bool = _terrain.terrain_surface_current()
	_layer_selectors["surface"].text = "Terrain surface *" if _terrain.terrain_surface != null and not current else "Terrain surface"
	_surface_status.text = "Surface ready. Play map uses this ground and the water layer." if current else "Build after generating heightmap and water. Previous surfaces are retained but hidden when either source changes."

func build_terrain_surface() -> void:
	if _surface_busy or _water_busy or _province_busy:
		return
	var error := regeneration_error("surface")
	if not error.is_empty() or not _terrain.water_layer_current():
		_surface_status.text = error if not error.is_empty() else "Generate rivers / lakes for the current heightmap first."
		return
	var serial := _water_job_serial
	var source: PackedFloat32Array = _terrain.map_renderer.normalized_heights.duplicate()
	var size: Vector2i = _terrain.sample_size()
	var fingerprint: String = _terrain.water_source_hash
	var water: RefCounted = _terrain.water_layer
	_surface_busy = true
	_surface_generate.disabled = true
	for control in _surface_controls.values():
		control.apply()
	await get_tree().process_frame
	var choices: Dictionary = {}
	for key in _surface_controls:
		choices[key] = _surface_controls[key].value
	_surface_status.text = "Shaping beds and banks…"
	_surface_thread = Thread.new()
	var started := _surface_thread.start(func():
		var layer := TerrainSurface.new()
		return {"error": layer.build(source, size, fingerprint, water, choices), "layer": layer})
	if started != OK:
		_surface_thread = null
		_surface_busy = false
		_surface_generate.disabled = false
		_surface_status.text = "Could not start terrain surface build."
		return
	while _surface_thread.is_alive():
		await get_tree().process_frame
	var result: Dictionary = _surface_thread.wait_to_finish()
	_surface_thread = null
	_surface_busy = false
	_surface_generate.disabled = false
	if serial != _water_job_serial or not regeneration_error("surface").is_empty():
		_surface_status.text = "The document or layer state changed. Build again."
		return
	if not result.error.is_empty():
		_surface_status.text = result.error
		return
	error = _terrain.install_terrain_surface(result.layer)
	if not error.is_empty():
		_surface_status.text = error
	else:
		_update_surface_status()

func _build_province_controls() -> void:
	_label("Province view")
	var appearance := OptionButton.new()
	appearance.name = "ProvinceAppearance"
	appearance.add_item("Colored provinces")
	appearance.add_item("Borders only — no province fill")
	appearance.item_selected.connect(func(index: int): _terrain.set_province_fill(index == 0))
	_form.add_child(appearance)
	_build_border_appearance_controls()
	_label("Generate land and enclosed inland-water regions, then coastal sea regions. Generated lakes stay separate.").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label("Target mainland provinces")
	_province_count = SpinBox.new()
	_province_count.min_value = 1
	_province_count.max_value = 512
	_province_count.value = 64
	_form.add_child(_province_count)
	_button("Generate provinces", generate_provinces, null, "GenerateProvinces")
	_province_generate = _form.get_child(_form.get_child_count() - 1)
	_label("Target ocean regions")
	_ocean_count = SpinBox.new()
	_ocean_count.min_value = 1
	_ocean_count.max_value = 256
	_ocean_count.value = 24
	_form.add_child(_ocean_count)
	_ocean_style = OptionButton.new()
	_ocean_style.add_item("Coastal seas + borderless open ocean")
	_ocean_style.set_item_metadata(0, "coastal_band")
	_ocean_style.add_item("Legacy full-ocean zones")
	_ocean_style.set_item_metadata(1, "open")
	_form.add_child(_ocean_style)
	_label("Coastal sea reach (pixels at 1025)", 13)
	_coastal_reach = SpinBox.new()
	_coastal_reach.min_value = 8
	_coastal_reach.max_value = 256
	_coastal_reach.step = 4
	_coastal_reach.value = 64
	_form.add_child(_coastal_reach)
	_label("Coastal provinces stop at the selected reach. Unassigned water keeps its original colors. Borders only preserves all water colors. Large enclosed seas also support ocean provinces.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("Generate ocean borders", generate_ocean_borders, null, "GenerateOceans")
	_label("Click the map to inspect and name a land or ocean region.").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_province_name = LineEdit.new()
	_province_name.max_length = 128
	_province_name.placeholder_text = "Region name"
	_form.add_child(_province_name)
	_button("Apply region name", rename_province, null, "RenameProvince")
	_label("Nation borders")
	_province_nation = OptionButton.new()
	_province_nation.name = "ProvinceNation"
	_form.add_child(_province_nation)
	_button("Assign nation to selected province", _assign_province_nation)
	_button("Create nation color", _create_nation_dialog)
	_sync_nation_choices()
	_province_status = _label("Build the terrain surface first.", 13)
	_province_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_province_brush = ProvinceBorderBrush.new()
	add_child(_province_brush)
	_province_brush.configure(self)

func _select_province(id: int) -> void:
	if id > 0 and (_terrain.province_layer == null or id > _terrain.province_layer.records.size() or not _terrain.province_layer.records[id - 1].get("active", true)): id = 0
	_province_selected = id
	_sync_nation_choices()
	if _terrain.map_renderer != null:
		_terrain.map_renderer.material.set_shader_parameter("selected_province", id)
		_terrain.map_renderer.material.set_shader_parameter("merge_ids", PackedInt32Array())
		_terrain.map_renderer.material.set_shader_parameter("merge_count", 0)
	if _province_name != null:
		_province_name.text = _terrain.province_layer.records[id - 1].name if id > 0 else ""

func _sync_nation_choices() -> void:
	if _province_nation == null: return
	_province_nation.clear()
	_province_nation.add_item("Unassigned",0)
	_province_nation.disabled = _terrain.province_layer == null or _province_selected <= 0 or _terrain.province_layer.records[_province_selected-1].kind != "land" or not can_edit("provinces")
	if _terrain.province_layer == null: return
	for nation in _terrain.province_layer.nations:
		_province_nation.add_item(nation.name,nation.id)
	if _province_selected > 0:
		_province_nation.select(int(_terrain.province_layer.records[_province_selected-1].get("nation_id",0)))

func _assign_province_nation() -> void:
	if not _terrain.province_layer_current() or not can_edit("provinces") or _province_busy: return
	var error: String = _terrain.province_layer.assign_nation(_province_selected,_province_nation.get_selected_id())
	if not error.is_empty():
		_province_status.text = error
		return
	_terrain.refresh_water_layer()
	mark_dirty()

func _create_nation_dialog() -> void:
	if not _terrain.province_layer_current() or not can_edit("provinces") or _province_busy: return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Create nation color"
	var box := VBoxContainer.new()
	var title := LineEdit.new()
	title.placeholder_text = "Nation name"
	title.max_length = 128
	var color := ColorPickerButton.new()
	color.color = Color(0.7,0.16,0.12)
	color.edit_alpha = false
	box.add_child(title)
	box.add_child(color)
	dialog.add_child(box)
	add_child(dialog)
	var original_layer: RefCounted = _terrain.province_layer
	dialog.confirmed.connect(func():
		if _terrain.province_layer != original_layer or not _terrain.province_layer_current() or not can_edit("provinces") or _province_busy: return
		var id: int = _terrain.province_layer.add_nation(title.text,color.color)
		if id == 0: return
		_sync_nation_choices()
		_province_nation.select(id)
		mark_dirty())
	dialog.visibility_changed.connect(func():
		if not dialog.visible: dialog.queue_free())
	dialog.popup_centered(Vector2i(360,150))

func rename_province() -> void:
	if not _terrain.province_layer_current() or not can_edit("provinces") or _province_busy or _province_selected <= 0 or _province_selected > _terrain.province_layer.records.size():
		return
	var value := _province_name.text.strip_edges()
	if value.is_empty():
		_province_status.text = "Enter a region name."
		return
	_terrain.province_layer.records[_province_selected - 1].name = value
	mark_dirty()
	_refresh_selected_cell()

func _update_province_status() -> void:
	if _province_status == null or _province_busy:
		return
	var current: bool = _terrain.province_layer_current()
	_layer_selectors["provinces"].text = "Provinces *" if _terrain.province_layer != null and not current else "Provinces"
	if current:
		var oceans := 0
		var inland := 0
		var active := 0
		for record in _terrain.province_layer.records:
			if not record.get("active", true): continue
			active += 1
			if record.kind == "ocean": oceans += 1
			if record.kind == "inland_water": inland += 1
		_province_status.text = "%d land · %d inland water · %d ocean regions. Ocean generation preserves land and inland-water IDs; province regeneration replaces all IDs and names." % [active - oceans - inland, inland, oceans]
	else:
		_province_status.text = "Build the terrain surface, then generate provinces. Old data is retained but hidden when the source changes."
	if not current:
		_province_selected = 0
		_province_name.text = ""

func generate_provinces() -> void:
	if _province_brush != null: _province_brush.cancel()
	if _province_busy or _water_busy or _surface_busy:
		return
	var error := regeneration_error("provinces")
	if not error.is_empty() or not _terrain.terrain_surface_current():
		_province_status.text = error if not error.is_empty() else "Build the current terrain surface first."
		return
	var serial := _water_job_serial
	var source: PackedFloat32Array = _terrain.map_renderer.normalized_heights.duplicate()
	var surface: RefCounted = _terrain.terrain_surface
	var water: RefCounted = _terrain.water_layer
	surface.fingerprint()
	_province_busy = true
	_province_generate.disabled = true
	_province_count.apply()
	await get_tree().process_frame
	var count := int(_province_count.value)
	_province_status.text = "Growing connected provinces around terrain and water…"
	_province_thread = Thread.new()
	var started := _province_thread.start(func():
		var layer := WorldProvinces.new()
		var generation_error: String = layer.generate(source, surface, water, count)
		if generation_error.is_empty(): layer.build_connections(water)
		return {"error": generation_error, "layer": layer})
	if started != OK:
		_province_thread = null
		_province_busy = false
		_province_generate.disabled = false
		_province_status.text = "Could not start province generation."
		return
	while _province_thread.is_alive():
		await get_tree().process_frame
	var result: Dictionary = _province_thread.wait_to_finish()
	_province_thread = null
	_province_busy = false
	_province_generate.disabled = false
	if serial != _water_job_serial or not regeneration_error("provinces").is_empty():
		_province_status.text = "The document or layer state changed. Generate again."
		return
	if not result.error.is_empty():
		_province_status.text = result.error
		return
	error = _terrain.install_province_layer(result.layer)
	_select_province(0)
	_update_province_status()
	if not error.is_empty():
		_province_status.text = error

func generate_ocean_borders() -> void:
	if _province_busy or _water_busy or _surface_busy: return
	if not regeneration_error("provinces").is_empty() or not _terrain.province_layer_current():
		_province_status.text = "Generate current land provinces and show/unlock the layer first."
		return
	_province_brush.cancel()
	var original: RefCounted = _terrain.province_layer
	var candidate: RefCounted = original.editable_copy()
	var base: PackedFloat32Array = _terrain.map_renderer.normalized_heights.duplicate()
	var water: RefCounted = _terrain.water_layer
	var serial := _water_job_serial
	_province_busy = true
	_ocean_count.apply()
	_coastal_reach.apply()
	await get_tree().process_frame
	var count := int(_ocean_count.value)
	var style: String = _ocean_style.get_item_metadata(_ocean_style.selected)
	var reach := float(_coastal_reach.value)
	_province_status.text = "Generating connected ocean regions around the land…"
	_province_thread = Thread.new()
	var started := _province_thread.start(func():
		var generation_error: String = candidate.generate_oceans(base, water, count, style, reach)
		if generation_error.is_empty(): candidate.build_connections(water)
		return generation_error)
	if started != OK:
		_province_thread = null
		_province_busy = false
		_province_status.text = "Could not start ocean generation."
		return
	while _province_thread.is_alive(): await get_tree().process_frame
	var error: String = _province_thread.wait_to_finish()
	_province_thread = null
	_province_busy = false
	if serial != _water_job_serial or _terrain.province_layer != original or not regeneration_error("provinces").is_empty():
		_province_status.text = "The document or layer changed. Generate ocean borders again."
		return
	if error.is_empty(): error = _terrain.install_province_layer(candidate)
	_select_province(0)
	_update_province_status()
	if not error.is_empty(): _province_status.text = error

func _build_border_appearance_controls() -> void:
	_label("Border appearance")
	for spec in [["Province dash thickness","province_width",0.0,12.0,0.1],["Nation line thickness","nation_width",0.0,12.0,0.1],["Ocean line thickness","ocean_width",0.0,12.0,0.1],["Zoomed-out thickness (%)","distant_scale",10.0,100.0,5.0]]:
		_label(spec[0],13)
		var control := SpinBox.new()
		control.name = "Border_"+spec[1]
		control.update_on_text_changed = true
		control.min_value = spec[2]
		control.max_value = spec[3]
		control.step = spec[4]
		control.tooltip_text = "Maximum width in screen pixels. Zero hides this border type." if spec[1] != "distant_scale" else "Percentage of full thickness when viewing the whole map."
		_border_controls[spec[1]] = control
		_form.add_child(control)
	var smooth := CheckBox.new()
	smooth.name = "SmoothBorderContours"
	smooth.text = "Natural contours (reduce pixel steps)"
	smooth.tooltip_text = "Reconstruct shared polygon contours for lines and fills. Terrain-based province generation stays intact."
	_border_controls.smooth = smooth
	_form.add_child(smooth)
	_button("Apply border appearance",_apply_border_appearance,null,"ApplyBorderAppearance")
	_sync_border_appearance_controls()
func _sync_border_appearance_controls() -> void:
	for key in _border_controls:
		var control = _border_controls[key]
		if control is CheckBox: control.set_pressed_no_signal(_terrain.border_appearance[key])
		else: control.set_value_no_signal(_terrain.border_appearance[key]*(100.0 if key == "distant_scale" else 1.0))
func _apply_border_appearance() -> void:
	_stop_brush()
	var choices: Dictionary = {}
	for key in _border_controls:
		var control = _border_controls[key]
		if control is CheckBox: choices[key] = control.button_pressed
		else:
			choices[key] = control.value/(100.0 if key == "distant_scale" else 1.0)
	var error: String = _terrain.set_border_appearance(choices)
	if error.is_empty():
		mark_dirty()
		_status.text = "Border appearance applied. Save world to retain it."
	else: _status.text = error
