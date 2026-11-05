extends Node3D
## Runtime map has no authoring controls and uses the same canonical terrain renderer.
signal return_requested

const CROSSINGS := {"province_border":"Land border", "river_crossing":"River crossing", "strait":"Strait"}
var _neighbors := {}
var _origin := 0
var _destination := 0
var _directions: RichTextLabel
var _clear: Button
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
