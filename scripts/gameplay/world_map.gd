extends Node3D
## Runtime map has no authoring controls and uses the same canonical terrain renderer.
signal return_requested

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
	title.text = "WORLD MAP · Shaded relief · Seed " + $Terrain.map_seed
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_child(title)
	var back := Button.new()
	back.name = "ReturnToEditor"
	back.text = "Return to editor" if not return_requested.get_connections().is_empty() else "Exit map"
	back.custom_minimum_size.y = 36
	back.pressed.connect(_request_return)
	toolbar.add_child(back)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_request_return()

func _request_return() -> void:
	if return_requested.get_connections().is_empty():
		get_tree().quit()
	else:
		return_requested.emit()
