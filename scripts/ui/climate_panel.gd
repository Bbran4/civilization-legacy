extends PanelContainer
## Runtime climate editor; all controls stage settings until Apply climate.
const Climate = preload("res://scripts/domain/terrain_climate.gd")
const Gizmo = preload("res://scripts/ui/climate_gizmo.gd")
var terrain: Node
var gizmo: Control
var controls: Dictionary = {}
var overlay: OptionButton
var status: Label
var latitude_label: Label
var legend: Label
var _form: VBoxContainer
var _syncing: bool = false


func _ready() -> void:
	name = "ClimatePanel"
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -294
	offset_top = -455
	offset_right = -14
	offset_bottom = -14
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14212c")
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 6)
	scroll.add_child(_form)
	_label("CLIMATE", 16)
	gizmo = Gizmo.new()
	_form.add_child(gizmo)
	gizmo.edited.connect(_gizmo_edited)
	latitude_label = _label("", 12)
	_number("Latitude span", "latitude_span", 10, 180, 1, "Choose how much of the planet your map covers from north to south, using a smaller span to move a regional map closer to a pole.")
	_number("Warmth offset (°C)", "temperature_bias", -20, 20, 1, "Add or remove up to 20 degrees from the calculated temperatures; this is an adjustment, not a 20-degree temperature cap.")
	_number("Rainfall (×)", "rainfall_scale", 0, 3, 0.1, "Make the map drier or wetter, where 1 is normal and 0 means no rain.")
	var apply := Button.new()
	apply.name = "ApplyClimate"
	apply.text = "Apply climate"
	apply.tooltip_text = "Generate temperature, winds and rainfall using this gizmo without changing the terrain."
	apply.pressed.connect(apply_settings)
	_form.add_child(apply)
	overlay = OptionButton.new()
	for title in ["Terrain", "Temperature", "Rainfall", "Winds"]:
		overlay.add_item(title)
	overlay.tooltip_text = "Terrain shows the resulting biomes, while the other views show the climate data that created them."
	overlay.item_selected.connect(func(index: int): terrain.set_climate_view(index); _update_legend())
	_form.add_child(overlay)
	legend = _label("", 12)
	status = _label("", 12)
	terrain.climate_changed.connect(sync)
	sync()


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	_form.add_child(label)
	return label


func _number(title: String, key: String, low: float, high: float, step: float, hint: String) -> void:
	var row := HBoxContainer.new()
	_form.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = hint
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.custom_minimum_size.x = 100
	spin.select_all_on_focus = true
	spin.tooltip_text = hint
	spin.get_line_edit().tooltip_text = hint
	spin.value_changed.connect(func(_value: float): _changed())
	row.add_child(spin)
	controls[key] = spin


func sync() -> void:
	_syncing = true
	for key in controls:
		controls[key].set_value_no_signal(terrain.climate_settings[key])
	gizmo.latitude_center = terrain.climate_settings.latitude_center
	gizmo.latitude_span = terrain.climate_settings.latitude_span
	gizmo.wind_rotation = terrain.climate_settings.wind_rotation
	gizmo.queue_redraw()
	_update_latitudes()
	if terrain.climate != null:
		status.text = "Temperatures %.0f to %.0f°C · %.0f ms" % [terrain.climate.temperature_range.x, terrain.climate.temperature_range.y, terrain.climate.generation_ms]
	else:
		status.text = "Generate terrain to add climate."
	_update_legend()
	_syncing = false


func _gizmo_edited(center: float, rotation: float) -> void:
	gizmo.latitude_center = center
	gizmo.wind_rotation = rotation
	_changed()


func _changed() -> void:
	if _syncing:
		return
	gizmo.latitude_span = controls.latitude_span.value
	gizmo.latitude_center = clampf(gizmo.latitude_center, -90 + gizmo.latitude_span * 0.5, 90 - gizmo.latitude_span * 0.5)
	gizmo.queue_redraw()
	_update_latitudes()
	status.text = "Changes ready · press Apply climate."


func _update_latitudes() -> void:
	latitude_label.text = "Top %+.0f° · Bottom %+.0f°\nDrag globe = latitude · Dial = wind offset" % [gizmo.latitude_center + gizmo.latitude_span * 0.5, gizmo.latitude_center - gizmo.latitude_span * 0.5]


func _update_legend() -> void:
	legend.text = ["Terrain shows climate-driven biomes · click a cell for its biome.", "Blue −80°C · white 0°C · red +60°C", "Sand 0 · teal 1500 · blue 6000 mm/yr (est.)", "Arrows point where air travels · not wind speed"][overlay.selected]


func apply_settings() -> void:
	for control in controls.values():
		control.apply()
	# SpinBox commits submitted text through deferred native signals.
	await get_tree().process_frame
	var options: Dictionary = {"latitude_center": gizmo.latitude_center, "latitude_span": gizmo.latitude_span, "temperature_bias": controls.temperature_bias.value, "rainfall_scale": controls.rainfall_scale.value, "wind_rotation": gizmo.wind_rotation}
	var error: String = terrain.apply_climate(options)
	if not error.is_empty():
		status.text = error
