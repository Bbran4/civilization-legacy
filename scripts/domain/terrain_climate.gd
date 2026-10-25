extends RefCounted
## Deterministic annual climate approximation; no weather, runoff or biomes.
const VERSION: int = 1
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const DEFAULTS: Dictionary = {"latitude_center": 0.0, "latitude_span": 140.0, "temperature_bias": 0.0, "rainfall_scale": 1.0, "wind_rotation": 0.0}
const LIMITS: Dictionary = {"latitude_center": [-85.0, 85.0], "latitude_span": [10.0, 180.0], "temperature_bias": [-20.0, 20.0], "rainfall_scale": [0.0, 3.0], "wind_rotation": [-180.0, 180.0]}
var settings: Dictionary = DEFAULTS.duplicate()
var source_hash: String = ""
var size := Vector2i.ZERO
var temperature := PackedFloat32Array()
var temperature_range := Vector2(INF, -INF)
var rainfall := PackedFloat32Array()
var winds := PackedVector2Array()
var field := PackedFloat32Array()
var generation_ms: float = 0.0


static func validate(value: Variant) -> String:
	if not value is Dictionary or value.size() != DEFAULTS.size():
		return "Climate settings must contain the five climate controls."
	for key in DEFAULTS:
		var item: Variant = value.get(key)
		if not (item is int or item is float) or not is_finite(float(item)) or item < LIMITS[key][0] or item > LIMITS[key][1]:
			return "Invalid climate setting: " + key
	if absf(value.latitude_center) + value.latitude_span * 0.5 > 90.00001:
		return "The latitude range must stay between the poles."
	return ""


static func latitude_at(uv_y: float, options: Dictionary) -> float:
	return options.latitude_center + (0.5 - uv_y) * options.latitude_span


static func wind_at(latitude: float, rotation: float) -> Vector2:
	var north: float = 1.0 if latitude >= 0.0 else -1.0
	var band: float = absf(latitude)
	# Vectors point TOWARD the destination; map +Y is south.
	var wind := Vector2(-1.0, north * 0.35)
	if band >= 30.0 and band < 60.0:
		wind = Vector2(1.0, -north * 0.35)
	elif band >= 60.0:
		wind = Vector2(-1.0, north * 0.25)
	return wind.normalized().rotated(deg_to_rad(rotation))


func generate(geography: RefCounted, options: Dictionary) -> void:
	var started: int = Time.get_ticks_usec()
	settings = options.duplicate()
	temperature_range = Vector2(INF, -INF)
	source_hash = geography.source_hash
	size = Grid.sample_size_for(geography.map_size, 128)
	var count: int = size.x * size.y
	temperature.resize(count)
	rainfall.resize(count)
	winds.resize(count)
	var heights := PackedFloat32Array()
	heights.resize(count)
	var moisture := PackedFloat32Array()
	moisture.resize(count)
	var next := PackedFloat32Array()
	next.resize(count)
	var rain_loss := PackedFloat32Array()
	rain_loss.resize(count)
	var step_world: float = maxf(geography.map_size.x, geography.map_size.y) / 32.0
	var upstream := PackedVector2Array()
	upstream.resize(count)
	var sea := PackedByteArray()
	sea.resize(count)
	var evaporate := PackedFloat32Array()
	evaporate.resize(count)
	for y in range(size.y):
		var lat: float = latitude_at(float(y) / (size.y - 1), settings)
		var belt: float = absf(lat)
		var wind: Vector2 = wind_at(lat, settings.wind_rotation)
		# Wet tropics / midlatitude storms, drier subtropics and polar regions.
		var convection: float = 0.012 + 0.045 * exp(-pow(belt / 16.0, 2)) + 0.022 * exp(-pow((belt - 55.0) / 15.0, 2))
		for x in range(size.x):
			var i: int = y * size.x + x
			var uv := Vector2(x, y) / Vector2(size - Vector2i.ONE)
			var height: float = Grid.sample(geography.display_heights, geography.contour_size, uv)
			heights[i] = height
			sea[i] = 1 if height < 0.2 else 0
			# Canonical height 20..100 maps to 0..6000 climate metres.
			var altitude_km: float = maxf(0.0, height - 0.2) * 7.5
			temperature[i] = clampf(29.0 - 52.0 * pow(sin(deg_to_rad(belt)), 1.25) - altitude_km * 6.5 + settings.temperature_bias, -80.0, 60.0)
			temperature_range.x = minf(temperature_range.x, temperature[i])
			temperature_range.y = maxf(temperature_range.y, temperature[i])
			winds[i] = wind
			# Account for map aspect ratio when stepping in physical directions.
			var delta: Vector2 = wind * step_world / geography.map_size * Vector2(size - Vector2i.ONE)
			var up: Vector2 = (Vector2(x, y) - delta) / Vector2(size - Vector2i.ONE)
			upstream[i] = up
			var upstream_height: float = Grid.sample(geography.display_heights, geography.contour_size, up.clamp(Vector2.ZERO, Vector2.ONE))
			rain_loss[i] = clampf(convection + maxf(0.0, height - maxf(0.2, upstream_height)) * 2.5, 0.005, 0.85)
			evaporate[i] = clampf((temperature[i] + 25.0) / 60.0, 0.12, 1.0)
			moisture[i] = evaporate[i] if sea[i] else 0.2
	# Fixed budget and physical step: moisture can cross the whole map.
	# Open boundaries represent incoming maritime air, not a wrapping globe.
	for iteration in range(64):
		for i in range(count):
			var up: Vector2 = upstream[i]
			var incoming: float = 0.6 if up.x < 0.0 or up.y < 0.0 or up.x > 1.0 or up.y > 1.0 else Grid.sample(moisture, size, up)
			next[i] = lerpf(incoming, evaporate[i], 0.65) if sea[i] else incoming * (1.0 - rain_loss[i])
		var swap: PackedFloat32Array = moisture
		moisture = next
		next = swap
	field.resize(count * 4)
	for i in range(count):
		var up: Vector2 = upstream[i]
		var incoming: float = 0.6 if up.x < 0.0 or up.y < 0.0 or up.x > 1.0 or up.y > 1.0 else Grid.sample(moisture, size, up)
		# Annualised game estimate, not a calibrated precipitation forecast.
		rainfall[i] = clampf(incoming * rain_loss[i] * 26000.0 * settings.rainfall_scale, 0.0, 6000.0)
		field[i * 4] = (temperature[i] + 80.0) / 140.0
		field[i * 4 + 1] = rainfall[i] / 6000.0
		field[i * 4 + 2] = winds[i].x * 0.5 + 0.5
		field[i * 4 + 3] = winds[i].y * 0.5 + 0.5
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0


func cell_info(uv: Vector2) -> Dictionary:
	var wind: Vector2 = wind_at(latitude_at(uv.y, settings), settings.wind_rotation)
	return {"latitude": latitude_at(uv.y, settings), "temperature": Grid.sample(temperature, size, uv), "rainfall": Grid.sample(rainfall, size, uv), "wind": wind}


static func evaporative_demand(temperature_c: float) -> float:
	# Shared annual game proxy, in mm/year, for biome aridity and lake losses.
	return maxf(150.0, 400.0 + maxf(-5.0, temperature_c) * 45.0)
