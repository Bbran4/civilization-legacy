extends RefCounted
const Settings = preload("res://scripts/domain/forest_settings.gd")
var editor: Control
var enabled: CheckBox
var controls: Dictionary = {}
var status: Label
func configure(owner_editor: Control) -> void:
	editor = owner_editor
	editor._label("Trees",22)
	editor._label("Regional moisture controls density; colder regions favor conifers. Water, steep slopes and snowy ground stay clear. Terrain texture rock/snow limits also apply.",13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enabled = CheckBox.new()
	enabled.name = "AutomaticTrees"
	enabled.text = "Show generated trees"
	editor._form.add_child(enabled)
	for entry in [["Variation seed","variation",0,2147483647,1],["Tree budget","count",0,20000,1],["Forest coverage (%)","coverage",0,100,1],["Tree size","size",0.4,2.0,0.1],["Maximum slope (°)","max_slope",10,55,1],["Tree line (% height)","tree_line",45,95,1]]:
		var row: HBoxContainer = editor._row(entry[0])
		var control := SpinBox.new()
		control.min_value = entry[2]
		control.max_value = entry[3]
		control.step = entry[4]
		control.value = Settings.DEFAULTS[entry[1]]
		control.custom_minimum_size.x = 125
		control.select_all_on_focus = true
		row.add_child(control)
		controls[entry[1]] = control
	editor._button("Generate trees",generate,null,"GenerateTrees")
	editor._button("New forest variation",new_variation,null,"NewForestVariation")
	status = editor._label("",13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor._label("The budget is a maximum; suitable ground and spacing can leave fewer trees. Zoom in to inspect them. Ground, water and province data are preserved.",12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enabled.toggled.connect(func(_value: bool):
		if not editor._syncing: _apply(false,false))
func sync() -> void:
	var settings: Dictionary = editor._terrain.tree_settings
	enabled.set_pressed_no_signal(settings.enabled)
	for key in controls: controls[key].set_value_no_signal(settings[key])
	update_status()
func update_status() -> void:
	var terrain = editor._terrain
	if status == null: return
	if not terrain.tree_settings.enabled: status.text = "Trees are off. Generate trees to add a forest."; return
	if not terrain.tree_layer_visible: status.text = "Trees layer is hidden."; return
	if not terrain.shaded_relief: status.text = "Trees are hidden in raw height view."; return
	var count: int = terrain.forest_view.positions.size() if terrain.forest_view != null else 0
	status.text = "%d trees · budget %d · variation %d" % [count,terrain.tree_settings.count,terrain.tree_settings.variation]
func generate() -> void: _apply(true,false)
func new_variation() -> void: _apply(true,true)
func _apply(force_enable: bool, variation: bool) -> void:
	if not editor.can_edit("trees"):
		status.text = "Show and unlock Trees before changing the forest."
		enabled.set_pressed_no_signal(editor._terrain.tree_settings.enabled)
		return
	var settings: Dictionary = Settings.DEFAULTS.duplicate()
	for key in controls:
		controls[key].apply()
		settings[key] = int(controls[key].value) if key in ["count","variation"] else float(controls[key].value)
	settings.enabled = force_enable or enabled.button_pressed
	if variation: settings.variation = (int(settings.variation)+1)%2147483648
	var error: String = editor._terrain.apply_tree_settings(settings)
	if not error.is_empty(): status.text = error; return
	sync()
	editor.mark_dirty()
