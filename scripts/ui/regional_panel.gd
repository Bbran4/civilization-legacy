extends RefCounted
const Regions = preload("res://scripts/domain/world_regions.gd")
var editor: Control
var global_controls: Dictionary = {}
var local_controls: Dictionary = {}
var preview: OptionButton
var brush: CheckBox
var radius: SpinBox
var status: Label
var legend: Label
var selection := PackedByteArray()
var selection_texture: ImageTexture
var painting := false
var last := Vector2.INF
func configure(owner_editor: Control) -> void:
	editor = owner_editor
	selection.resize(Regions.SIZE*Regions.SIZE)
	editor._label("Regional controls",22)
	editor._label("Warmth and moisture guide ground colors, snow and forests. Adjustments are percentage points; height, rivers and provinces stay unchanged.",13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor._label("Preview",16)
	preview = OptionButton.new()
	for name in ["Natural terrain","Warmth coverage","Moisture coverage","Selected area"]: preview.add_item(name)
	editor._form.add_child(preview)
	preview.item_selected.connect(func(_index): update_preview())
	legend = editor._label("",12)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor._label("Whole map",16)
	global_controls = _controls("Global")
	editor._button("Regenerate whole map",apply_global,null,"RegenerateRegionsGlobal")
	editor._label("Selected area",16)
	local_controls = _controls("Selected")
	brush = CheckBox.new()
	brush.text = "Brush a selection on the map"
	editor._form.add_child(brush)
	brush.toggled.connect(func(value: bool):
		painting = false
		last = Vector2.INF
		if value:
			preview.select(3)
			update_preview())
	var row: HBoxContainer = editor._row("Selection radius · map units")
	radius = SpinBox.new()
	radius.min_value = 1
	radius.max_value = 512
	radius.value = 16
	row.add_child(radius)
	editor._label("Left-drag to select. The soft edge blends the change. Right/middle drag and wheel still control the camera.",12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	editor._form.add_child(actions)
	editor._button("Select all",func(): selection.fill(255); _refresh_selection(),actions)
	editor._button("Clear selection",func(): selection.fill(0); _refresh_selection(),actions)
	editor._button("Regenerate selected area",apply_selected,null,"RegenerateRegionsSelected")
	editor._button("Reset selected to generated",func(): apply_selected(true))
	editor._button("Undo regional change (Ctrl+Z)",undo)
	status = editor._label("",12)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor._button("Back to Ground paint",func(): editor._select_layer("paint"))
	_refresh_selection()
	sync()
func _controls(prefix: String) -> Dictionary:
	var result := {}
	for entry in [["Warmth adjustment","warmth",-50,50],["Moisture adjustment","moisture",-50,50],["Variation seed","variation",0,2147483647]]:
		var row: HBoxContainer = editor._row(entry[0])
		var spin := SpinBox.new()
		spin.name = prefix+entry[1]
		spin.min_value = entry[2]
		spin.max_value = entry[3]
		spin.step = 1
		spin.custom_minimum_size.x = 115
		spin.select_all_on_focus = true
		row.add_child(spin)
		result[entry[1]] = spin
	return result
func _read(controls: Dictionary) -> Dictionary:
	var value := {}
	for name in controls:
		controls[name].apply()
		value[name] = int(controls[name].value) if name == "variation" else float(controls[name].value)
	return value
func sync() -> void:
	for name in global_controls: global_controls[name].set_value_no_signal(editor._terrain.regional_controls.settings[name])
	var extent: Vector2 = editor._terrain.display_size()
	radius.min_value = maxf(1.0,maxf(extent.x,extent.y)/Regions.SIZE)
	selection.fill(0)
	_refresh_selection()
	if status != null: status.text = "Regional changes save with the world. Undo keeps up to 16 changes."
func active() -> bool: return editor._contexts.regions.visible
func stop() -> void:
	painting = false
	last = Vector2.INF
	if brush != null: brush.set_pressed_no_signal(false)
	_set_preview(preview.selected if preview != null and active() else 0)
func _set_preview(mode: int) -> void:
	var terrain = editor._terrain
	terrain.region_preview = mode
	if terrain.map_renderer != null:
		terrain.map_renderer.sync_water_surface(mode)
		terrain.map_renderer.material.set_shader_parameter("region_preview",mode)
		terrain.map_renderer.material.set_shader_parameter("region_selection",selection_texture)
	if terrain.forest_view != null: terrain.forest_view.update_presentation(terrain)
func update_preview() -> void:
	_set_preview(preview.selected if active() else 0)
	legend.text = ["Natural terrain; province visibility follows the layer controls.","Warmth after elevation cooling: blue = cold, yellow = mild, red = warm.","Moisture: brown = dry, green/blue = wet.","Yellow marks the selected area. Only this area changes when regenerated."][preview.selected]
func _refresh_selection() -> void:
	var image := Image.create_from_data(Regions.SIZE,Regions.SIZE,false,Image.FORMAT_R8,selection)
	if selection_texture == null: selection_texture = ImageTexture.create_from_image(image)
	else: selection_texture.update(image)
	if preview != null: update_preview()
	if status != null: status.text = "Selected %.1f%% of the map." % (100.0*(selection.size()-selection.count(0))/selection.size())
func _allowed() -> bool:
	if editor.can_edit("paint"): return true
	status.text = "Show and unlock Ground paint before editing regions."
	return false
func _finish(error: String) -> void:
	if not error.is_empty(): status.text = error; return
	editor._terrain.refresh_water_layer()
	update_preview()
	if editor._forest_panel != null: editor._forest_panel.update_status()
	editor.mark_dirty()
	status.text = "Regions updated. Geography and province IDs are unchanged."
func apply_global() -> void:
	if _allowed(): _finish(editor._terrain.regional_controls.apply_global(_read(global_controls)))
func apply_selected(reset: bool = false) -> void:
	if _allowed(): _finish(editor._terrain.regional_controls.apply_selected(editor._terrain.map_seed,selection,_read(local_controls),reset))
func undo() -> void:
	if _allowed() and editor._terrain.regional_controls.undo():
		for name in global_controls: global_controls[name].set_value_no_signal(editor._terrain.regional_controls.settings[name])
		_finish("")
func handle_input(event: InputEvent) -> bool:
	if not active(): return false
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_Z:
		undo()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var handled := painting
		painting = false
		last = Vector2.INF
		return handled
	if not brush.button_pressed or not editor.can_edit("paint"): return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		painting = true
		last = Vector2.INF
		_select(event.position)
		return true
	if event is InputEventMouseMotion and painting:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT: painting = false; return false
		_select(event.position)
		return true
	return false
func _select(screen: Vector2) -> void:
	var terrain = editor._terrain
	var camera: Camera3D = editor._camera_rig.get_node("Camera3D")
	var hit: Variant = terrain.ray_surface_hit(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	if hit == null: last = Vector2.INF; return
	hit = terrain.to_local(hit)
	var extent: Vector2 = terrain.display_size()
	var point := Vector2(hit.x,hit.z)+extent*0.5
	var start := point if last == Vector2.INF else last
	var spacing := maxf(radius.value*0.25,maxf(extent.x,extent.y)/Regions.SIZE*0.5)
	var steps := maxi(1,ceili(start.distance_to(point)/spacing))
	for i in range(1,steps+1): stamp(start.lerp(point,float(i)/steps)/extent,extent,radius.value)
	last = point
	_refresh_selection()
func stamp(uv: Vector2,extent: Vector2,brush_radius: float) -> void:
	brush_radius = maxf(brush_radius,maxf(extent.x,extent.y)/Regions.SIZE*0.75)
	var center := uv*Regions.SIZE-Vector2.ONE*0.5
	var span := Vector2.ONE*brush_radius/extent*Regions.SIZE
	var low := Vector2i((center-span).floor()).max(Vector2i.ZERO)
	var high := Vector2i((center+span).ceil()).min(Vector2i(Regions.SIZE-1,Regions.SIZE-1))
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var distance := ((Vector2(x,y)-center)/Regions.SIZE*extent).length()/brush_radius
			var strength := roundi((1.0-smoothstep(0.6,1.0,distance))*255)
			selection[y*Regions.SIZE+x] = maxi(selection[y*Regions.SIZE+x],strength)
