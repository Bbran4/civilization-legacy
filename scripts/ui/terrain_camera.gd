extends Node3D
## Orthographic terrain inspection camera. Does not modify generated map data.

signal zoom_changed

@export_range(20.0, 500.0, 1.0) var initial_view_size: float = 180.0
@export_range(5.0, 200.0, 1.0) var movement_speed: float = 60.0
@export var sidebar_width: float = 380.0
var _yaw: float = 0.0
var _pitch: float = 55.0
var _map_size := Vector2.ZERO
var _fit_size: float = 180.0
var _zoom: float = 1.0
@export_range(0.1, 20.0, 0.1) var min_zoom: float = 1.0:
	set(value):
		min_zoom = clampf(value, 0.1, max_zoom)
		_apply_zoom()
@export_range(1.0, 8192.0, 1.0) var max_zoom: float = 2048.0:
	set(value):
		max_zoom = clampf(value, min_zoom, 8192.0)
		_apply_zoom()
@export_range(0.5, 128.0, 0.5) var closest_view_size: float = 8.0:
	set(value):
		closest_view_size = clampf(value, 0.5, 128.0)
		_apply_zoom()
var _sun_shadows_enabled: bool = true
var _sun_shadow_opacity: float = 1.0
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	var sun = get_parent().get_node_or_null("Sun")
	if sun is DirectionalLight3D:
		_sun_shadows_enabled = sun.shadow_enabled
		_sun_shadow_opacity = sun.shadow_opacity
	_reset_view()
	get_parent().get_node("Terrain").terrain_regenerated.connect(_map_changed)
	get_viewport().size_changed.connect(_reset_view)


func _map_changed() -> void:
	if get_parent().get_node("Terrain").display_size() != _map_size:
		_reset_view()
	else:
		_fit_depth()


func _process(delta: float) -> void:
	_camera.h_offset = -0.5 * _camera.size * minf(sidebar_width, get_viewport().get_visible_rect().size.x * 0.5) / maxf(1.0, get_viewport().get_visible_rect().size.y)
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:
		return
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y -= 1.0
	if direction != Vector2.ZERO:
		var forward: Vector3 = _pan_down()
		global_position += (_camera.global_basis.x * direction.normalized().x + forward.normalized() * direction.normalized().y) * movement_speed * delta * (_camera.size / initial_view_size)
		_fit_depth()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var terrain = get_parent().get_node("Terrain")
			var anchor: Variant = terrain.ray_surface_hit(_camera.project_ray_origin(event.position), _camera.project_ray_normal(event.position))
			_zoom *= 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			_apply_zoom()
			if anchor != null:
				var after: Variant = Plane(Vector3.UP, anchor.y).intersects_ray(_camera.project_ray_origin(event.position), _camera.project_ray_normal(event.position))
				if after != null:
					var shift: Vector3 = anchor - after
					shift.y = 0.0
					global_position += shift
					_fit_depth()
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_yaw -= event.relative.x * 0.25
			_pitch = clampf(_pitch + event.relative.y * 0.2, 25.0, 85.0)
			_apply_pose()
			_fit_depth()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var forward: Vector3 = _pan_down()
			var scale_per_pixel: float = _camera.size / get_viewport().get_visible_rect().size.y
			global_position += (-_camera.global_basis.x * event.relative.x - forward * event.relative.y) * scale_per_pixel
			_fit_depth()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		_reset_view()


func _reset_view() -> void:
	position = Vector3.ZERO
	_yaw = 0.0
	_pitch = 55.0
	rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var terrain = get_parent().get_node("Terrain")
	_map_size = terrain.display_size()
	var bounds: Vector2 = terrain.height_bounds()
	position.y = (bounds.x + bounds.y) * 0.5
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available_width: float = maxf(200.0, viewport_size.x - sidebar_width - 40.0)
	var width_fit: float = _map_size.x * viewport_size.y / available_width
	var height_fit: float = _map_size.y
	_fit_size = maxf(width_fit, height_fit) * 1.12
	_zoom = 1.0
	_apply_zoom()



func zoom_limits() -> Vector2:
	var limit: float = maxf(1.0, minf(max_zoom, _fit_size / closest_view_size))
	return Vector2(minf(min_zoom, limit), limit)


func zoom_to_limit(closest: bool) -> void:
	if not closest:
		_reset_view()
	var limits: Vector2 = zoom_limits()
	_zoom = limits.y if closest else limits.x
	_apply_zoom()


func _apply_zoom() -> void:
	var limits: Vector2 = zoom_limits()
	_zoom = clampf(_zoom, limits.x, limits.y)
	if is_instance_valid(_camera):
		_apply_pose()
		_camera.size = _fit_size / _zoom
		_camera.h_offset = -0.5 * _camera.size * minf(sidebar_width, get_viewport().get_visible_rect().size.x * 0.5) / maxf(1.0, get_viewport().get_visible_rect().size.y)
		_fit_depth()
	zoom_changed.emit()


func _apply_pose() -> void:
	var overview: float = 1.0 - smoothstep(1.0, 3.0, _zoom)
	var terrain = get_parent().get_node("Terrain")
	if terrain.is_flat_map_mode():
		overview = 1.0
	var pitch: float = lerpf(_pitch, 90.0, overview)
	rotation_degrees = Vector3(-pitch, _yaw * (1.0 - overview), 0.0)
	terrain.set_overview_blend(overview)
	var sun = get_parent().get_node_or_null("Sun")
	if sun is DirectionalLight3D:
		sun.shadow_opacity = _sun_shadow_opacity * (1.0 - overview)
		sun.shadow_enabled = _sun_shadows_enabled and overview < 0.999


func _pan_down() -> Vector3:
	# Camera up retains a usable horizontal direction at exactly 90 degrees.
	var down := -_camera.global_basis.y
	down.y = 0.0
	return down.normalized()


func _fit_depth() -> void:
	# An orthographic map needs the depth of the visible terrain, not the full
	# horizontal world diameter; an oversized frustum wastes shadow precision.
	var terrain = get_parent().get_node("Terrain")
	var bounds: Vector2 = terrain.height_bounds()
	var height_range: float = bounds.y - bounds.x + absf(position.y - (bounds.x + bounds.y) * 0.5) * 2.0
	var depth: float = (height_range + _camera.size * 2.0 + 4.0) / maxf(0.3, absf(_camera.global_basis.z.y))
	_camera.position.z = depth + 32.0
	_camera.near = 1.0
	_camera.far = depth * 2.0 + 64.0
	if terrain.detail != null and terrain.detail.active:
		var visible_bounds: Vector2 = terrain.detail.visible_depth_bounds(_camera, global_position)
		if visible_bounds.x <= visible_bounds.y:
			_camera.position.z = maxf(32.0, visible_bounds.y + 32.0)
			_camera.near = maxf(1.0, _camera.position.z - visible_bounds.y - 8.0)
			_camera.far = maxf(_camera.near + 16.0, _camera.position.z - visible_bounds.x + 8.0)
	var sun = get_parent().get_node_or_null("Sun")
	if sun is DirectionalLight3D:
		sun.directional_shadow_max_distance = _camera.far
