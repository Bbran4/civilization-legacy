extends Node
const Texturing = preload("res://scripts/domain/terrain_texturing.gd")
var texture_enabled: CheckBox
var texture_controls: Dictionary = {}
var texture_status: Label
var editor: Control
var enabled: CheckBox
var radius: SpinBox
var color: ColorPickerButton
var erase: CheckBox
var painting := false
var last := Vector2.INF
func configure(owner_editor: Control) -> void:
	editor = owner_editor
	editor._label("Ground paint",22)
	editor._label("Automatic ground textures",16)
	texture_enabled = CheckBox.new()
	texture_enabled.name = "AutomaticTextures"
	texture_enabled.text = "Auto-generate terrain textures"
	editor._form.add_child(texture_enabled)
	for entry in [["Variation seed","variation",0,2147483647,1],["Texture scale","scale",1,32,0.5],["Grass cover (%)","grass_cover",0,100,1],["Rock slope (°)","rock_angle",15,75,1],["Snow height (%)","snow_height",35,100,1]]:
		var row: HBoxContainer = editor._row(entry[0])
		var control := SpinBox.new()
		control.name = "Texture_"+entry[1]
		control.custom_minimum_size.x = 125
		control.select_all_on_focus = true
		control.min_value = entry[2]
		control.max_value = entry[3]
		control.step = entry[4]
		control.value = Texturing.DEFAULTS[entry[1]]
		row.add_child(control)
		texture_controls[entry[1]] = control
	editor._button("Generate textures",func(): apply_textures(true),null,"GenerateTextures")
	editor._button("New texture variation",new_texture_variation,null,"NewTextureVariation")
	texture_status = editor._label("",12)
	texture_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texture_enabled.toggled.connect(func(_value: bool):
		if not editor._syncing: apply_textures(false))
	editor._label("Grass, soil, sand, rock and snow follow the terrain automatically. Manual paint stays above them. Choose Borders only in Provinces to see the terrain without political colors.",12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor._button("Regional controls…",editor._show_regions,null,"RegionalControls")
	editor._label("Manual ground paint",16)
	editor._label("Paint over generated textures. Water and province overlays stay above it.",13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enabled = CheckBox.new()
	enabled.text = "Enable ground brush"
	editor._form.add_child(enabled)
	enabled.toggled.connect(func(value: bool):
		if not value: cancel())
	editor._label("Paint color",13)
	color = ColorPickerButton.new()
	color.custom_minimum_size.y = 36
	color.color = Color("738958")
	editor._form.add_child(color)
	editor._label("Brush radius · map units",13)
	radius = SpinBox.new()
	radius.min_value = 1
	radius.max_value = 128
	radius.value = 12
	editor._form.add_child(radius)
	erase = CheckBox.new()
	erase.text = "Erase paint"
	editor._form.add_child(erase)
	editor._button("Undo ground stroke (Ctrl+Z)",undo)
	editor._button("Clear ground paint",clear)
	editor._label("Left drag to paint · Up to 16 undo steps\nSave world includes this layer.",13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
func cancel() -> void:
	painting = false
	last = Vector2.INF
func undo() -> void:
	if editor.selected_layer == "paint" and editor.can_edit("paint") and editor._terrain.map_paint.undo(): editor.mark_dirty()
func clear() -> void:
	if editor.can_edit("paint"):
		editor._terrain.map_paint.clear()
		editor.mark_dirty()
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var handled := painting
		cancel()
		return handled
	if editor.selected_layer != "paint" or not editor.can_edit("paint"): cancel(); return false
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_Z:
		undo()
		return true
	if not enabled.button_pressed: return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		last = Vector2.INF
		editor._terrain.map_paint.begin_stroke()
		painting = true
		_apply(event.position)
		return true
	if event is InputEventMouseMotion and painting:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT: cancel(); return false
		_apply(event.position)
		return true
	return false
func _apply(screen: Vector2) -> void:
	var terrain = editor._terrain
	var camera: Camera3D = editor._camera_rig.get_node("Camera3D")
	var hit: Variant = terrain.ray_surface_hit(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	if hit != null: hit = terrain.to_local(hit)
	if hit == null: last = Vector2.INF; return
	var point: Vector2 = Vector2(hit.x,hit.z)+terrain.map_size*0.5
	if point.x < 0 or point.y < 0 or point.x > terrain.map_size.x or point.y > terrain.map_size.y: last = Vector2.INF; return
	var start: Vector2 = point if last == Vector2.INF else last
	var steps := maxi(1,ceili(start.distance_to(point)/maxf(0.5,radius.value*0.25)))
	for i in range(1,steps+1):
		terrain.map_paint.stamp(start.lerp(point,float(i)/steps)/terrain.map_size,terrain.map_size,radius.value,color.color,erase.button_pressed)
	terrain.map_paint.refresh()
	last = point
	editor.mark_dirty()

func sync_textures() -> void:
	var settings: Dictionary = editor._terrain.texture_settings
	texture_enabled.set_pressed_no_signal(settings.enabled)
	for key in texture_controls: texture_controls[key].set_value_no_signal(settings[key])
	texture_status.text = "Automatic textures ready · variation %d" % settings.variation if settings.enabled else "Automatic textures off · original shading is visible."

func apply_textures(force_enable: bool = true) -> void:
	if not editor.can_edit("paint"):
		texture_status.text = "Show and unlock Ground paint before changing textures."
		texture_enabled.set_pressed_no_signal(editor._terrain.texture_settings.enabled)
		return
	_commit_textures(_read_texture_settings(force_enable))

func _read_texture_settings(force_enable: bool) -> Dictionary:
	var settings: Dictionary = Texturing.DEFAULTS.duplicate()
	for key in texture_controls:
		texture_controls[key].apply()
		settings[key] = int(texture_controls[key].value) if key == "variation" else float(texture_controls[key].value)
	settings.enabled = force_enable or texture_enabled.button_pressed
	return settings

func _commit_textures(settings: Dictionary) -> void:
	var error: String = editor._terrain.apply_automatic_textures(settings)
	if not error.is_empty(): texture_status.text = error; return
	sync_textures()
	editor.mark_dirty()

func new_texture_variation() -> void:
	if not editor.can_edit("paint"): apply_textures(true); return
	var settings := _read_texture_settings(true)
	settings.variation = (int(settings.variation)+1) % 2147483648
	_commit_textures(settings)
