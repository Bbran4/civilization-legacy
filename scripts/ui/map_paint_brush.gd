extends Node
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
	editor._label("Paint over terrain shading. Water and province overlays stay above it.",13).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	# The generation overview is a flat plane, even when relief shading is active.
	var hit: Variant = Plane(Vector3.UP,0).intersects_ray(terrain.to_local(camera.project_ray_origin(screen)),terrain.global_basis.inverse()*camera.project_ray_normal(screen))
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
