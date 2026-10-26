extends Control
## Runtime controls stage generation settings; save/load operate on the visible map.

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
	_build_cell_inspector()
	var climate_panel := ClimatePanel.new()
	climate_panel.terrain = _terrain
	add_child(climate_panel)


func _build_interface() -> void:
	var editor_theme := Theme.new()
	editor_theme.default_font_size = 14
	editor_theme.set_color("font_color", "Label", Color("dce5e9"))
	theme = editor_theme
	var panel := PanelContainer.new()
	panel.name = "Sidebar"
	panel.anchor_bottom = 1.0
	panel.offset_left = 14
	panel.offset_top = 14
	panel.offset_right = 370
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
	_label("CIVILIZATION LEGACY", 13, Color("afbdc6"))
	_label("Terrain editor", 28, Color("f0dbab"))
	_label("Create a heightmap. Keep the world.", 14)
	var files := HBoxContainer.new()
	_form.add_child(files)
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
	var actions := HBoxContainer.new()
	_form.add_child(actions)
	_button("Generate", apply_settings, actions, "Generate")
	_button("New seed", _new_seed, actions, "NewSeed")
	var automatic := _label("Terrain detail and colours are chosen automatically.", 13, Color("a9bdc8"))
	automatic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status = _label("Ready", 13, Color("d7c18d"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(0, 125)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_form.add_child(_preview)
	_help(_preview, "preview")
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
	_help(button, title)
	if not node_name.is_empty():
		button.name = node_name
	button.custom_minimum_size.y = 32
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	(parent if parent != null else _form).add_child(button)


func _sync_from_terrain() -> void:
	_syncing = true
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


func apply_settings() -> void:
	var picker := _controls["terrain_template"] as OptionButton
	_terrain.terrain_template = picker.get_item_metadata(picker.selected)
	_terrain.map_size = Vector2(_controls["map_size.x"].value, _controls["map_size.y"].value)
	_terrain.map_seed = (_controls["map_seed"] as LineEdit).text
	_terrain.heightmap_texture = _pending_image
	_terrain.source_heightmap_path = _image_path
	_terrain.source_heightmap_size = _image_size
	GenerationProfile.apply(_terrain)
	_terrain.island_enabled = (_controls["island_enabled"] as CheckBox).button_pressed
	_terrain.elevation = _controls["elevation"].value
	_terrain.snow_height = _terrain.elevation * 0.55
	_terrain.regenerate()
	# Normalize an empty seed in the control to match the generated map.
	(_controls["map_seed"] as LineEdit).text = _terrain.map_seed
	_update_preview()
	get_parent().get_parent().get_node("CameraRig")._reset_view()


func _new_seed() -> void:
	(_controls["map_seed"] as LineEdit).text = str(randi_range(1, 2147483647))
	apply_settings()


func _update_preview() -> void:
	_preview.texture = ImageTexture.create_from_image(_terrain.heightmap_image())
	_status.text = "Current map: %s\n%d × %d · Seed %s\nCreated in %.2f seconds" % [_terrain.source_heightmap_path.get_file() if _terrain.heightmap_texture != null else _terrain.terrain_template, _terrain.map_size.x, _terrain.map_size.y, _terrain.map_seed, _terrain.generation_ms / 1000.0]


func _show_dialog(action: String) -> void:
	_dialog_action = action
	_dialog.current_dir = ProjectSettings.globalize_path("user://maps")
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action in ["load", "image"] else FileDialog.FILE_MODE_SAVE_FILE
	match action:
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
		"save":
			var error: String = Document.save_file(path, _terrain)
			_status.text = "Saved " + path.get_file() if error.is_empty() else error
		"load":
			load_terrain(path)
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
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -274
	panel.offset_right = -14
	panel.offset_top = 14
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


func _reset_cell_inspector() -> void:
	_selected_cell = -1
	_cell_label.text = "CELL DATA\nClick the map to inspect its terrain." if _terrain.graph != null else "LEGACY TERRAIN\nGenerate to create cell data."
	_cell_panel.anchor_bottom = 0.0
	_cell_panel.offset_bottom = 84



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var camera: Camera3D = get_parent().get_parent().get_node("CameraRig/Camera3D")
		var info: Dictionary = _terrain.pick_cell(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
		if not info.is_empty():
			_selected_cell = info.id
			_show_cell_info(info)


func _refresh_selected_cell() -> void:
	if _selected_cell >= 0:
		var info: Dictionary = _terrain.cell_info(_selected_cell)
		if not info.is_empty():
			_show_cell_info(info)


func _show_cell_info(info: Dictionary) -> void:
	_cell_panel.anchor_bottom = 1.0
	_cell_panel.offset_bottom = -470
	_cell_label.text = "CELL %d · %s\nX %.2f   Y %.2f\nHeight %d / 100 · sea datum 20\n%d neighbors\nArea %.2f map units²" % [info.id, info.get("surface_kind", "Land" if info.land else "Water"), info.position.x, info.position.y, info.height, info.neighbor_count, info.area]
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
		_cell_label.text += "\nBiome: %s\nLatitude: %+.1f°\nTemperature: %.1f°C\nRainfall: %.0f mm/yr (est.)\nWind travels: %s" % [info.biome, info.latitude, info.temperature, info.rainfall, _wind_name(info.wind)]
		if info.has("canopy"):
			_cell_label.text += "\nPotential tree cover: %.0f%% · nearby water: %.0f%%" % [info.canopy * 100.0, info.water_support * 100.0]
		if info.has("tree_count"):
			_cell_label.text += "\nPlaced trees in this cell: %d" % info.tree_count




func _wind_name(wind: Vector2) -> String:
	var bearing: float = fposmod(rad_to_deg(atan2(wind.x, -wind.y)), 360.0)
	return ["North", "North-east", "East", "South-east", "South", "South-west", "West", "North-west"][roundi(bearing / 45.0) % 8]
