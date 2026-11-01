extends Node
## Routes brush gestures before cell inspection and draws a depth-tested footprint.
var editor: Node
var terrain: Node
var enabled: CheckBox
var eraser: CheckBox
var row: OptionButton
var slot: OptionButton
var radius: SpinBox
var strength: SpinBox
var status: Label
var preview: MeshInstance3D
var painting := false
var last_point := Vector2.INF
var _time: float = 0

func configure(owner_editor: Node) -> void:
	editor = owner_editor
	terrain = editor._terrain
	editor._section("GROUND PAINTING")
	editor._button("Ground textures…", editor._open_ground_palette, null, "GroundTextures")
	enabled = CheckBox.new()
	enabled.text = "Paint ground"
	enabled.tooltip_text = "Turn on the brush, then drag the left mouse button across the map."
	editor._form.add_child(enabled)
	row = OptionButton.new()
	for index in range(terrain.surface_catalog.rows.size()):
		row.add_item(terrain.surface_catalog.rows[index].label)
		row.set_item_disabled(index, index in [0, 12])
	row.select(4)
	row.tooltip_text = "Choose the biome or surface whose textures you want to paint."
	editor._form.add_child(row)
	slot = OptionButton.new()
	for text in ["Biome mix", "Texture 1", "Texture 2", "Texture 3"]:
		slot.add_item(text)
	slot.tooltip_text = "Paint all three textures together, or pick one texture slot."
	editor._form.add_child(slot)
	radius = _number("Brush radius", 0.5, 128, 0.5, 8, "Choose how wide the brush reaches from its centre.")
	strength = _number("Brush strength", 0.05, 1, 0.05, 1, "Lower values paint more gently; repeated passes build coverage.")
	eraser = CheckBox.new()
	eraser.text = "Erase paint"
	eraser.tooltip_text = "Remove painted coverage and reveal the generated ground underneath."
	editor._form.add_child(eraser)
	editor._button("Undo paint stroke", undo, null, "UndoPaint")
	editor._button("Clear ground paint", clear, null, "ClearPaint")
	status = editor._label("Paint changes appearance; climate and terrain stay intact.", 12, Color("a9bdc8"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview = MeshInstance3D.new()
	preview.name = "GroundBrushPreview"
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0.9, 0.5)
	preview.material_override = material
	terrain.add_child(preview)
	preview.visible = false

func _number(label: String, low: float, high: float, step: float, value: float, tip: String) -> SpinBox:
	editor._label(label, 13)
	var control := SpinBox.new()
	control.min_value = low
	control.max_value = high
	control.step = step
	control.value = value
	control.tooltip_text = tip
	editor._form.add_child(control)
	return control

func choose(row_id: int, selected: int) -> void:
	row.select(row_id)
	slot.select(selected + 1)
	enabled.button_pressed = true
	eraser.button_pressed = false
	status.text = "Drag on the map to paint. Save terrain to keep the strokes."

func _hit(position: Vector2) -> Variant:
	var camera: Camera3D = editor._camera_rig._camera
	var hit: Variant = terrain.ray_surface_hit(camera.project_ray_origin(position), camera.project_ray_normal(position))
	if hit == null:
		return null
	var local: Vector3 = terrain.to_local(hit)
	return Vector2(local.x, local.z) + terrain.map_size * 0.5

func handle_input(event: InputEvent) -> bool:
	if enabled == null or not enabled.button_pressed:
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_Z and event.ctrl_pressed:
		undo()
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and terrain.climate_view == 0 and not terrain.heightmap_view:
			var point: Variant = _hit(event.position)
			if point != null:
				terrain.paint_layer.begin_stroke()
				last_point = point
				painting = true
				_paint(point)
		else:
			painting = false
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseMotion and painting:
		get_viewport().set_input_as_handled()
		return true
	return false

func _paint(point: Vector2) -> void:
	terrain.paint_layer.stroke(last_point if last_point.is_finite() else point, point, radius.value, strength.value, row.selected, slot.selected - 1, eraser.button_pressed)
	terrain.update_painted_surface()
	last_point = point
	status.text = "Erasing ground paint…" if eraser.button_pressed else "Painting " + row.get_item_text(row.selected) + ". Save terrain to keep it."

func _process(delta: float) -> void:
	_time += delta
	if _time < 1.0 / 30.0 or preview == null:
		return
	_time = 0
	if not enabled.button_pressed or terrain.climate_view != 0 or terrain.heightmap_view or get_viewport().gui_get_hovered_control() != null:
		preview.visible = false
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			painting = false
		return
	var point: Variant = _hit(get_viewport().get_mouse_position())
	preview.visible = point != null
	if point == null:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in range(65):
		var angle: float = index * TAU / 64.0
		var edge: Vector2 = point + Vector2(cos(angle), sin(angle)) * radius.value
		var height: float = terrain.visible_surface_height(edge / terrain.map_size) + 0.04 * terrain.relief_scale()
		mesh.surface_add_vertex(Vector3(edge.x - terrain.map_size.x * 0.5, height, edge.y - terrain.map_size.y * 0.5))
	mesh.surface_end()
	preview.mesh = mesh
	if painting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_paint(point)
	else:
		painting = false

func undo() -> void:
	painting = false
	last_point = Vector2.INF
	if terrain.paint_layer.undo():
		terrain.update_painted_surface()
		status.text = "Undid the last paint stroke."
	else:
		status.text = "No paint strokes to undo."

func clear() -> void:
	painting = false
	if terrain.paint_layer.image == null:
		return
	terrain.paint_layer.begin_stroke()
	terrain.paint_layer.image = null
	terrain.paint_layer.texture = null
	terrain.update_painted_surface()
	status.text = "Ground paint cleared. Undo restores it."
