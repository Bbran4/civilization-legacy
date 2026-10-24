extends Control
## Drag the latitude band on a globe, or rotate the wind-offset compass.
signal edited(center: float, rotation: float)
var latitude_center: float = 0.0
var latitude_span: float = 140.0
var wind_rotation: float = 0.0
var _drag: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(250, 112)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Drag the globe up or down to place your map on the planet, or drag the compass to turn the winds."


func _draw() -> void:
	var globe := Vector2(62, 55)
	var radius: float = 46.0
	draw_circle(globe, radius, Color("214659"))
	var polygon := PackedVector2Array()
	var north: float = latitude_center + latitude_span * 0.5
	var south: float = latitude_center - latitude_span * 0.5
	for i in range(33):
		var lat: float = lerpf(north, south, float(i) / 32)
		polygon.append(globe + Vector2(cos(deg_to_rad(lat)), -sin(deg_to_rad(lat))) * radius)
	for i in range(33):
		var lat: float = lerpf(south, north, float(i) / 32)
		polygon.append(globe + Vector2(-cos(deg_to_rad(lat)), -sin(deg_to_rad(lat))) * radius)
	draw_colored_polygon(polygon, Color(0.55, 0.76, 0.45, 0.75))
	for lat in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var y: float = -sin(deg_to_rad(lat)) * radius
		var width: float = cos(deg_to_rad(lat)) * radius
		draw_line(globe + Vector2(-width, y), globe + Vector2(width, y), Color(0.8, 0.9, 1.0, 0.35))
	var y: float = -sin(deg_to_rad(latitude_center)) * radius
	var width: float = cos(deg_to_rad(latitude_center)) * radius
	draw_line(globe + Vector2(-width, y), globe + Vector2(width, y), Color("ffdc8b"), 3.0, true)
	draw_arc(globe, radius, 0, TAU, 64, Color("a9bdc8"), 1, true)
	var compass := Vector2(195, 55)
	draw_arc(compass, 34, 0, TAU, 48, Color("a9bdc8"), 1, true)
	var direction: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(wind_rotation))
	var tip: Vector2 = compass + direction * 28
	draw_line(compass - direction * 22, tip, Color("ffdc8b"), 3, true)
	draw_line(tip, tip - direction.rotated(0.6) * 13, Color("ffdc8b"), 3, true)
	draw_line(tip, tip - direction.rotated(-0.6) * 13, Color("ffdc8b"), 3, true)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(52, 10), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(52, 111), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(163, 10), "Turn winds", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(178, 111), "%+.0f°" % wind_rotation, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = (1 if event.position.x < 125 else 2) if event.pressed else 0
		if event.pressed:
			_drag_to(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _drag != 0:
		_drag_to(event.position)
		accept_event()


func _drag_to(point: Vector2) -> void:
	if _drag == 1:
		latitude_center = clampf(rad_to_deg(asin(clampf((55.0 - point.y) / 46.0, -1, 1))), -90 + latitude_span * 0.5, 90 - latitude_span * 0.5)
	else:
		wind_rotation = rad_to_deg((point - Vector2(195, 55)).angle())
	edited.emit(latitude_center, wind_rotation)
	queue_redraw()
