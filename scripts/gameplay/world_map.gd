extends Node3D
## Runtime map has no authoring controls and uses the same canonical terrain renderer.
signal return_requested
var menu_session := false

const CROSSINGS := {"province_border":"Land border", "river_crossing":"River crossing", "strait":"Strait"}
var _neighbors := {}
var _origin := 0
var _destination := 0
var _directions: RichTextLabel
var _clear: Button
var _settlement := 0
var _unit := 0
var _turn := 1
var _orders: Array[int] = []
var _status: Label
var _found: Button
var _select_unit: Button
var _order: Button
var _end_turn: Button
var _home_marker: Label3D
var _unit_marker: Label3D
var _route_colors: ImageTexture

func _ready() -> void:
	var hud := CanvasLayer.new()
	hud.name = "MapHUD"
	add_child(hud)
	var toolbar := HBoxContainer.new()
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_left = 14
	toolbar.offset_right = -14
	toolbar.offset_top = 10
	hud.add_child(toolbar)
	var title := Label.new()
	var update_title := func():
		title.text = "WORLD MAP · " + ("Updating terrain view…" if $Terrain.map_renderer != null and $Terrain.map_renderer.display_pending() else "Shaded relief · Seed " + $Terrain.map_seed)
	update_title.call()
	$Terrain.presentation_changed.connect(update_title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_child(title)
	if $Terrain.province_layer_current():
		_setup_routes(hud)
		var provinces := CheckButton.new()
		provinces.button_pressed = $Terrain.province_layer_visible
		provinces.text = "Provinces"
		provinces.toggled.connect($Terrain.set_province_layer_visible)
		toolbar.add_child(provinces)
		var appearance := OptionButton.new()
		appearance.name = "ProvinceAppearance"
		appearance.add_item("Colored provinces")
		appearance.add_item("Borders only")
		appearance.select(0 if $Terrain.province_fill else 1)
		appearance.item_selected.connect(func(index: int): $Terrain.set_province_fill(index == 0))
		toolbar.add_child(appearance)
	var back := Button.new()
	back.name = "ReturnToEditor"
	back.text = "Return to editor" if not return_requested.get_connections().is_empty() else "Exit map"
	if menu_session: back.text = "Main menu"
	back.custom_minimum_size.y = 36
	back.pressed.connect(_request_return)
	toolbar.add_child(back)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _directions != null:
		var camera := get_viewport().get_camera_3d()
		var hit: Variant = $Terrain.ray_surface_hit(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
		if hit != null:
			var local: Vector3 = $Terrain.to_local(hit)
			var uv: Vector2 = Vector2(local.x, local.z) / $Terrain.display_size() + Vector2.ONE * 0.5
			_pick_province($Terrain.province_layer.id_at(uv))
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_request_return()

func _request_return() -> void:
	if return_requested.get_connections().is_empty():
		get_tree().quit()
	else:
		return_requested.emit()

func _setup_routes(hud: CanvasLayer) -> void:
	for edge in $Terrain.province_layer.connections:
		if not CROSSINGS.has(edge.type): continue
		for pair in [Vector2i(edge.a, edge.b), Vector2i(edge.b, edge.a)]:
			if not _neighbors.has(pair.x): _neighbors[pair.x] = {}
			# Prefer a dry crossing when a shared boundary offers both.
			if not _neighbors[pair.x].has(pair.y) or edge.type == "province_border":
				_neighbors[pair.x][pair.y] = edge.type
	var panel := PanelContainer.new()
	panel.position = Vector2(14,58)
	hud.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_directions = RichTextLabel.new()
	_directions.custom_minimum_size = Vector2(284,100)
	box.add_child(_directions)
	_clear = Button.new()
	_clear.text = "Clear route"
	_clear.pressed.connect(_reset_route)
	box.add_child(_clear)
	_status = Label.new()
	box.add_child(_status)
	_found = _action(box, "Found tribal settlement here", _found_settlement)
	_select_unit = _action(box, "Select scout", _focus_unit)
	_order = _action(box, "Order scout to destination", _issue_order)
	_end_turn = _action(box, "End turn", _advance_turn)
	_reset_route()

func _reset_route() -> void:
	_origin = 0
	_destination = 0
	_clear.disabled = true
	_directions.text = "Route preview\nClick a land province to start."
	_show_route([])

func _pick_province(id: int) -> void:
	var records: Array = $Terrain.province_layer.records
	if id <= 0 or records[id - 1].kind != "land":
		if _origin == 0: _directions.text = "Choose a land province to start."
		elif _destination == 0: _directions.text = "From %s\nChoose a land province as the destination." % records[_origin - 1].name
		return
	if _origin == 0 or _destination != 0 or id == _origin:
		_origin = id
		_destination = 0
		_clear.disabled = false
		_directions.text = str(records[id - 1].name) + "\nClick a destination."
		_show_route([id])
		return
	_destination = id
	var path := _find_route(_origin, id)
	if path.is_empty():
		_directions.text = "No land or strait route from %s to %s.\nClick to start another route." % [records[_origin - 1].name, records[id - 1].name]
		_show_route([_origin,id])
		return
	var lines := PackedStringArray(["%s → %s" % [records[_origin - 1].name, records[id - 1].name]])
	for i in range(1, path.size()):
		lines.append("%s → %s" % [CROSSINGS[_neighbors[path[i-1]][path[i]]], records[path[i]-1].name])
	lines.append("Click to start another route.")
	_directions.text = "\n".join(lines)
	_show_route(path)

func _find_route(start: int, finish: int) -> Array[int]:
	var queue: Array[int] = [start]
	var parent := {}
	parent[start] = 0
	var cursor := 0
	while cursor < queue.size() and not parent.has(finish):
		var here := queue[cursor]
		cursor += 1
		for next in _neighbors.get(here, {}):
			if parent.has(next): continue
			parent[next] = here
			queue.append(next)
	var path: Array[int] = []
	if parent.has(finish):
		var current := finish
		while current != 0:
			path.append(current)
			current = parent[current]
		path.reverse()
	return path

func _show_route(path: Array) -> void:
	_update_actions(path)
	var material: ShaderMaterial = $Terrain.map_renderer.material
	material.set_shader_parameter("route_enabled", not path.is_empty())
	if path.is_empty(): return
	var colors := Image.create(256,256,false,Image.FORMAT_RGBA8)
	colors.fill(Color.TRANSPARENT)
	for id: int in path:
		var color := Color("#ebba51")
		if id == _origin: color = Color("#50c5aa")
		elif id == _destination: color = Color("#f48b51")
		colors.set_pixel(id % 256, id / 256, color)
	if _route_colors == null: _route_colors = ImageTexture.create_from_image(colors)
	else: _route_colors.update(colors)
	material.set_shader_parameter("route_colors", _route_colors)
	material.set_shader_parameter("route_provinces", $Terrain.province_layer.texture())

func _action(box: VBoxContainer, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	box.add_child(button)
	return button

func _update_actions(path: Array) -> void:
	_found.visible = _settlement == 0
	_found.disabled = _origin == 0 or _destination != 0
	_select_unit.visible = _unit != 0
	_order.visible = _unit != 0
	_order.disabled = _origin != _unit or _destination == 0 or path.size() < 2 or not _neighbors.get(path[0], {}).has(path[1])
	_end_turn.visible = _unit != 0
	if _unit == 0:
		_status.text = "Choose a starting province to found a settlement."
		return
	var records: Array = $Terrain.province_layer.records
	_status.text = "Turn %d  |  Scout at %s" % [_turn, records[_unit - 1].name]
	if not _orders.is_empty():
		_status.text += "\nTo %s (%d turns)" % [records[_orders.back() - 1].name, _orders.size()]

func _found_settlement() -> void:
	if _settlement != 0 or _origin == 0 or _destination != 0: return
	_settlement = _origin
	_unit = _origin
	_home_marker = _marker("Tribal settlement", Color.WHEAT)
	_unit_marker = _marker("Scout", Color.AQUAMARINE)
	_place_markers()
	_focus_unit()

func _focus_unit() -> void:
	if _unit == 0: return
	_origin = 0
	_pick_province(_unit)

func _issue_order() -> void:
	if _unit == 0 or _origin != _unit or _destination == 0: return
	var path := _find_route(_unit, _destination)
	if path.size() < 2: return
	_orders.assign(path.slice(1))
	_update_actions(path)

func _advance_turn() -> void:
	if _unit == 0: return
	_turn += 1
	if not _orders.is_empty():
		_unit = _orders.pop_front()
		_place_markers()
	_focus_unit()
	if not _orders.is_empty(): _pick_province(_orders.back())

func _marker(caption: String, tint: Color) -> Label3D:
	var marker := Label3D.new()
	marker.text = caption
	marker.modulate = tint
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.fixed_size = true
	marker.pixel_size = 0.001
	marker.font_size = 18
	$Terrain.add_child(marker)
	return marker

func _place_markers() -> void:
	var layer: RefCounted = $Terrain.province_layer
	for marker: Label3D in [_home_marker, _unit_marker]:
		var province := _settlement if marker == _home_marker else _unit
		var pixel: int = layer.ids.find(province)
		var uv := Vector2(pixel % layer.size.x, pixel / layer.size.x) / Vector2(layer.size - Vector2i.ONE)
		var horizontal: Vector2 = (uv - Vector2.ONE * 0.5) * $Terrain.display_size()
		marker.position = Vector3(horizontal.x, $Terrain.visible_surface_height(uv), horizontal.y)
		marker.offset.y = 20 if marker == _unit_marker and _unit == _settlement else 0
