extends Node
const History = preload("res://scripts/domain/province_edit_history.gd")
var editor: Node
var enabled: CheckBox
var attach_islands: CheckBox
var radius: SpinBox
var status: Label
var history := History.new()
var painting := false
var last := Vector2.INF
var preview: MeshInstance3D
func configure(owner_editor: Node) -> void:
	editor = owner_editor
	enabled = CheckBox.new()
	enabled.text = "Paint region borders"
	enabled.toggled.connect(func(value: bool):
		if not value: cancel())
	editor._form.add_child(enabled)
	editor._label("Pick a region, then paint to expand it or absorb an island. Alt-click picks another region. Land and ocean cannot overwrite each other.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attach_islands = CheckBox.new()
	attach_islands.text = "Attach whole separate islands"
	attach_islands.button_pressed = true
	editor._form.add_child(attach_islands)
	editor._label("Touch a separate island to absorb it into the selected land province. Turn this off to paint island pixels individually.", 12).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor._label("Brush radius (pixels at 1025)", 13)
	radius = SpinBox.new()
	radius.min_value = 0.5
	radius.max_value = 64
	radius.step = 0.5
	radius.value = 6
	editor._form.add_child(radius)
	editor._button("Undo border stroke (Ctrl+Z)", undo, null, "UndoBorder")
	editor._button("Redo border stroke (Ctrl+Y)", redo, null, "RedoBorder")
	status = editor._label("Land provinces can span islands. Painting over a whole land province absorbs it. Undo restores it.", 12)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview = MeshInstance3D.new()
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0.9, 0.3)
	preview.material_override = material
	editor._terrain.add_child(preview)
	preview.visible = false
func allowed() -> bool:
	return editor.selected_layer == "provinces" and editor.can_edit("provinces") and editor._terrain.province_layer_current() and not editor._province_busy and not editor._water_busy and not editor._surface_busy
func _hit(position: Vector2) -> Variant:
	var camera: Camera3D = editor._camera_rig._camera
	var hit: Variant = editor._terrain.ray_surface_hit(camera.project_ray_origin(position), camera.project_ray_normal(position))
	if hit == null: return null
	var local: Vector3 = editor._terrain.to_local(hit)
	var uv: Vector2 = Vector2(local.x, local.z) / editor._terrain.display_size() + Vector2.ONE * 0.5
	if uv.x < 0 or uv.y < 0 or uv.x > 1 or uv.y > 1: return null
	return uv * Vector2(editor._terrain.province_layer.size - Vector2i.ONE)
func handle_input(event: InputEvent) -> bool:
	if not allowed(): return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and painting:
		cancel()
		status.text = "Unfinished stroke cancelled."
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		if event.keycode == KEY_Z:
			if event.shift_pressed: redo()
			else: undo()
			get_viewport().set_input_as_handled()
			return true
		if event.keycode == KEY_Y:
			redo()
			get_viewport().set_input_as_handled()
			return true
	if not enabled.button_pressed: return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			finish()
		else:
			var point: Variant = _hit(event.position)
			if point == null: return false
			if event.alt_pressed:
				cancel()
				editor._select_province(editor._terrain.province_layer.id_at(point / Vector2(editor._terrain.province_layer.size - Vector2i.ONE)))
			elif history.begin(editor._terrain.province_layer, editor._province_selected):
				painting = true
				last = point
				_paint(point)
			else: status.text = "Pick a land or ocean region before painting."
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseMotion and painting:
		var point: Variant = _hit(event.position)
		if point != null: _paint(point)
		else: last = Vector2.INF
		get_viewport().set_input_as_handled()
		return true
	return false
func _input(event: InputEvent) -> void:
	if painting and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		finish()
func _paint(point: Vector2) -> void:
	if not allowed() or history.current != editor._terrain.province_layer:
		cancel()
		return
	var r: float = radius.value * maxi(history.draft.size.x, history.draft.size.y) / 1025.0
	history.stroke(last if last.is_finite() else point, point, r, attach_islands.button_pressed)
	last = point
	editor._terrain.map_renderer.set_provinces(history.draft, true)
func finish() -> void:
	if not painting: return
	painting = false
	if not allowed() or history.current != editor._terrain.province_layer:
		cancel()
		return
	_apply_result(history.finish(), "Border stroke applied.")
func _apply_result(result: Dictionary, success: String) -> void:
	editor._terrain.refresh_water_layer()
	if not result.error.is_empty():
		status.text = result.error
		return
	if result.layer != null:
		var error: String = editor._terrain.install_province_layer(result.layer)
		status.text = success if error.is_empty() else error
		editor._refresh_selected_cell()
func undo() -> void:
	if not allowed(): return
	cancel()
	_apply_result(history.undo(editor._terrain.province_layer), "Undid border stroke.")
func redo() -> void:
	if not allowed(): return
	cancel()
	_apply_result(history.redo(editor._terrain.province_layer), "Redid border stroke.")
func cancel() -> void:
	painting = false
	last = Vector2.INF
	history.cancel()
	if preview != null: preview.visible = false
	if editor != null: editor._terrain.refresh_water_layer()
func _process(_delta: float) -> void:
	if not allowed():
		if painting: cancel()
		preview.visible = false
		return
	if painting and history.current != editor._terrain.province_layer: cancel()
	history.sync(editor._terrain.province_layer)
	if painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): finish()
	if not enabled.button_pressed or get_viewport().gui_get_hovered_control() != null:
		preview.visible = false
		if painting: last = Vector2.INF
		return
	var point: Variant = _hit(get_viewport().get_mouse_position())
	preview.visible = point != null
	if point == null: return
	var dimensions: Vector2i = editor._terrain.province_layer.size
	var r: float = radius.value * maxi(dimensions.x, dimensions.y) / 1025.0
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for j in range(49):
		var edge: Vector2 = (point + Vector2(cos(j * TAU / 48), sin(j * TAU / 48)) * r) / Vector2(dimensions - Vector2i.ONE) - Vector2.ONE * 0.5
		edge *= editor._terrain.display_size()
		mesh.surface_add_vertex(Vector3(edge.x, 0.05, edge.y))
	mesh.surface_end()
	preview.mesh = mesh
