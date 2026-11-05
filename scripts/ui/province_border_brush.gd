extends Node
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const History = preload("res://scripts/domain/province_edit_history.gd")
var editor: Node
var mode: OptionButton
var tool_help: Label
var merge_action: Button
var merge_info: Label
var merge_ids: Array[int] = []
var merge_source: RefCounted
var split_points := PackedVector2Array()
var split_source: RefCounted
var radius_label: Label
var island_help: Label
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
	editor._label("Province tool", 13)
	mode = OptionButton.new()
	for label in ["Paint borders", "Draw split border", "Merge provinces", "Erase to impassable land"]: mode.add_item(label)
	mode.item_selected.connect(_set_mode)
	editor._form.add_child(mode)
	enabled = CheckBox.new()
	enabled.text = "Paint region borders"
	enabled.toggled.connect(func(value: bool):
		if not value: cancel())
	editor._form.add_child(enabled)
	tool_help = editor._label("Pick a region to paint or restore erased land. With no selection, painting erased land creates a new province. Alt-click changes target.", 12)
	tool_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attach_islands = CheckBox.new()
	attach_islands.text = "Attach whole separate islands"
	attach_islands.button_pressed = true
	editor._form.add_child(attach_islands)
	island_help = editor._label("Touch a separate island to absorb it into the selected land province. Turn this off to paint island pixels individually.", 12)
	island_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	radius_label = editor._label("Brush radius (pixels at 1025)", 13)
	radius = SpinBox.new()
	radius.min_value = 0.5
	radius.max_value = 64
	radius.step = 0.5
	radius.value = 6
	editor._form.add_child(radius)
	merge_info = editor._label("Pick the province to keep, then click additional regions.", 12)
	merge_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	merge_info.visible = false
	editor._button("Merge selected provinces", merge_selected, null, "MergeProvinces")
	merge_action = editor._form.get_child(editor._form.get_child_count() - 1)
	merge_action.visible = false
	merge_action.disabled = true
	editor._button("Undo province edit (Ctrl+Z)", undo, null, "UndoBorder")
	editor._button("Redo province edit (Ctrl+Y)", redo, null, "RedoBorder")
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
		status.text = "Unfinished province edit cancelled."
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
			var id: int = editor._terrain.province_layer.id_at(point / Vector2(editor._terrain.province_layer.size - Vector2i.ONE))
			if event.alt_pressed:
				cancel()
				editor._select_province(id)
			elif mode.selected == 2:
				_toggle_merge(id)
			elif mode.selected == 1:
				var layer: RefCounted = editor._terrain.province_layer
				if editor._province_selected <= 0:
					status.text = "Pick a province before drawing a split."
				else:
					history.sync(layer)
					split_source = layer
					split_points = PackedVector2Array([point])
					painting = true
			elif _begin_paint(point):
				painting = true
				last = point
				_paint(point)
			else: status.text = "Pick a land or ocean region before painting."
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseMotion and painting:
		var point: Variant = _hit(event.position)
		if mode.selected == 1:
			if point != null and split_points[-1].distance_to(point) >= 0.5: split_points.append(point)
		elif point != null: _paint(point)
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
	editor._terrain.map_renderer.set_provinces(history.draft, true, true)
func finish() -> void:
	if not painting: return
	painting = false
	if not allowed() or history.current != editor._terrain.province_layer:
		cancel()
		return
	if mode.selected == 1:
		if split_source != editor._terrain.province_layer:
			cancel()
			return
		var result := history.split(editor._terrain.province_layer, editor._province_selected, split_points)
		split_points.clear()
		split_source = null
		_apply_result(result, "Province split. The original keeps its ID and name.")
		if result.get("new_id", 0) > 0: editor._select_province(result.new_id)
	else:
		_apply_result(history.finish(), "Land marked impassable." if mode.selected == 3 else "Border stroke applied.")
func _apply_result(result: Dictionary, success: String) -> void:
	editor._terrain.refresh_water_layer()
	if not result.error.is_empty():
		status.text = result.error
		return
	if result.layer != null:
		var error: String = editor._terrain.install_province_layer(result.layer)
		status.text = success if error.is_empty() else error
		editor._refresh_selected_cell()
		editor._select_province(editor._province_selected)
		if result.get("new_id", 0) > 0: editor._select_province(result.new_id)
		if result.get("select_id", 0) > 0: editor._select_province(result.select_id)
func undo() -> void:
	if not allowed(): return
	cancel()
	_apply_result(history.undo(editor._terrain.province_layer), "Undid province edit.")
func redo() -> void:
	if not allowed(): return
	cancel()
	_apply_result(history.redo(editor._terrain.province_layer), "Redid province edit.")
func cancel() -> void:
	painting = false
	last = Vector2.INF
	history.cancel()
	split_points.clear()
	split_source = null
	_clear_merge()
	if preview != null: preview.visible = false
	if editor != null: editor._terrain.refresh_water_layer()
func _process(_delta: float) -> void:
	if not allowed():
		if painting or not merge_ids.is_empty(): cancel()
		preview.visible = false
		return
	if history.current != editor._terrain.province_layer and (painting or not merge_ids.is_empty()): cancel()
	history.sync(editor._terrain.province_layer)
	if painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): finish()
	if painting and mode.selected == 1:
		_draw_split()
		return
	if mode.selected == 2:
		preview.visible = false
		return
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
	var previous := Vector2.INF
	var extent: Vector2 = editor._terrain.display_size()
	for j in range(49):
		var uv: Vector2 = (point + Vector2(cos(j * TAU / 48), sin(j * TAU / 48)) * r) / Vector2(dimensions - Vector2i.ONE)
		var points := PackedVector2Array([uv]) if previous == Vector2.INF else Grid.split_surface_segment(previous,uv,editor._terrain.map_renderer.surface_grid_size())
		for at in points:
			var edge := (at-Vector2.ONE*0.5)*extent
			mesh.surface_add_vertex(Vector3(edge.x,editor._terrain.visible_surface_height(at)+0.08,edge.y))
		previous = uv
	mesh.surface_end()
	preview.mesh = mesh

func _set_mode(_index: int) -> void:
	cancel()
	enabled.set_pressed_no_signal(false)
	enabled.text = ["Paint region borders", "Draw split border", "Pick provinces to merge", "Erase to impassable land"][mode.selected]
	tool_help.text = ["Pick a region to expand it or restore erased land. With no selection, painting erased land creates a new province. Alt-click picks a region.", "Select a province, enable the tool, then drag a line across it or draw a closed loop. Alt-click changes the selected province. Release to split; Escape cancels.", "Select the province whose ID/name you want to keep. Enable the tool and click additional provinces. Alt-click changes the kept province. Then Merge selected provinces.", "Drag over land to remove its province coverage and mark it impassable. Paint borders restores erased land into a selected land province. Water is protected."][mode.selected]
	for control in [attach_islands, island_help]: control.visible = mode.selected == 0
	for control in [radius, radius_label]: control.visible = mode.selected in [0,3]
	preview.material_override.albedo_color = Color(1,0.3,0.2) if mode.selected == 3 else Color(1,0.9,0.3)
	merge_info.visible = mode.selected == 2
	merge_action.visible = mode.selected == 2

func _clear_merge() -> void:
	merge_ids.clear()
	merge_source = null
	if merge_action != null: merge_action.disabled = true
	if merge_info != null: merge_info.text = "Pick the province to keep, then click additional regions."
	if editor != null and editor._terrain.map_renderer != null:
		editor._terrain.map_renderer.material.set_shader_parameter("merge_count", 0)

func _toggle_merge(id: int) -> void:
	var layer: RefCounted = editor._terrain.province_layer
	if id <= 0:
		status.text = "Unassigned water has no province to merge."
		return
	if editor._province_selected <= 0: editor._select_province(id)
	var keep: int = editor._province_selected
	if layer.records[id - 1].kind != layer.records[keep - 1].kind:
		status.text = "Select only land provinces or only coastal sea regions."
		return
	if merge_source != null and merge_source != layer: _clear_merge()
	history.sync(layer)
	merge_source = layer
	if merge_ids.is_empty(): merge_ids.append(keep)
	if id != keep:
		if id in merge_ids: merge_ids.erase(id)
		elif merge_ids.size() < 32: merge_ids.append(id)
		else:
			status.text = "Merge up to 32 regions at once."
			return
	var labels := PackedStringArray()
	for selected in merge_ids: labels.append("%s (#%d)" % [layer.records[selected - 1].name, selected])
	merge_info.text = "Keep %s (#%d).\nSelected: %s" % [layer.records[keep - 1].name, keep, ", ".join(labels)]
	merge_action.disabled = merge_ids.size() < 2
	var highlighted := PackedInt32Array()
	highlighted.resize(32)
	for i in range(merge_ids.size()): highlighted[i] = merge_ids[i]
	layer = editor._terrain.province_layer
	editor._terrain.map_renderer.material.set_shader_parameter("merge_ids", highlighted)
	editor._terrain.map_renderer.material.set_shader_parameter("merge_count", merge_ids.size())

func merge_selected() -> void:
	if not allowed(): return
	if merge_source != editor._terrain.province_layer:
		_clear_merge()
		status.text = "The region map changed. Select provinces again."
		return
	painting = false
	var result := history.merge(editor._terrain.province_layer, editor._province_selected, merge_ids.duplicate())
	_clear_merge()
	_apply_result(result, "Provinces merged. The selected province keeps its ID and name.")

func _draw_split() -> void:
	preview.visible = split_points.size() > 1
	if split_points.size() < 2: return
	var dimensions: Vector2i = editor._terrain.province_layer.size
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var previous := Vector2.INF
	var extent: Vector2 = editor._terrain.display_size()
	var mesh_size: Vector2i = editor._terrain.map_renderer.surface_grid_size()
	for pixel in split_points:
		var local: Vector2 = (pixel / Vector2(dimensions - Vector2i.ONE) - Vector2.ONE * 0.5) * extent
		var start := local if previous == Vector2.INF else previous
		for uv in Grid.split_surface_segment(start/extent+Vector2.ONE*0.5,local/extent+Vector2.ONE*0.5,mesh_size):
			var point := (uv-Vector2.ONE*0.5)*extent
			mesh.surface_add_vertex(Vector3(point.x,editor._terrain.visible_surface_height(point/extent+Vector2.ONE*0.5)+0.08,point.y))
		previous = local
	mesh.surface_end()
	preview.mesh = mesh

func _begin_paint(point: Vector2) -> bool:
	var layer: RefCounted = editor._terrain.province_layer
	if mode.selected == 3: return history.begin_erase(layer)
	if editor._province_selected > 0: return history.begin(layer,editor._province_selected)
	var p := Vector2i(point.round()).clamp(Vector2i.ZERO,layer.size-Vector2i.ONE)
	return history.begin_new_land(layer,p.y*layer.size.x+p.x)
