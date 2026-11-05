extends RefCounted
## Adapts arbitrary sea datums to the existing hydrology's normalized 0.2 datum.
## Native source heights are immutable. Only the derived output contains bed carving.
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Surface = preload("res://scripts/domain/terrain_surface.gd")
var water: RefCounted
var surface: RefCounted
var heights := PackedFloat32Array()
var levels := PackedFloat32Array()
var river_focus := Vector3.ZERO
var has_river_focus := false

func build(image: Image, sea: float, runoff: Image, density: float, river_width: float, depth: float) -> String:
	if image == null or image.is_empty() or image.get_format() != Image.FORMAT_RF or not is_finite(sea) or sea < 0 or sea > 1 or runoff == null:
		return "Hydrology requires float height samples, a sea datum and a runoff field."
	var size := image.get_size()
	var base := image.get_data().to_float32_array()
	var working := PackedFloat32Array()
	working.resize(base.size())
	for i in range(base.size()):
		working[i] = _to_working(base[i], sea)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	hash.update(runoff.get_data())
	hash.update(JSON.stringify([sea, density, river_width, depth]).to_utf8_buffer())
	var fingerprint := hash.finish().hex_encode()
	var choices: Dictionary = Water.DEFAULTS.duplicate()
	choices.routing_resolution = 513
	choices.density = density
	choices.width = river_width
	choices.lake_depth = 0.003
	choices.lake_area = 0.005
	water = Water.new()
	var error: String = water.generate(working, size, fingerprint, choices, runoff)
	if not error.is_empty():
		return error
	surface = Surface.new()
	error = surface.build(working, size, fingerprint, water, {"river_depth": depth, "lake_depth": depth * 1.5, "bank_width": 3.0})
	if not error.is_empty():
		return error
	heights.resize(base.size())
	levels.resize(base.size())
	for i in range(base.size()):
		# Dry samples with no bank shaping preserve the original float bits.
		heights[i] = base[i] if surface.heights[i] == working[i] else _from_working(surface.heights[i], sea)
		levels[i] = -1.0 if water.surface_levels[i] < 0 else _from_working(water.surface_levels[i], sea)
	var best_score := 0.0
	for feature in water.river_features:
		var profile: PackedFloat32Array = feature.profile
		var score: float = profile.size() * log(1.0 + float(feature.flow))
		if score > best_score:
			best_score = score
			var middle := (profile.size() / 8) * 4
			river_focus = Vector3(profile[middle], _from_working(profile[middle + 3], sea), profile[middle + 1])
			has_river_focus = true
	return ""

static func _to_working(height: float, sea: float) -> float:
	return 0.2 * height / maxf(sea, 0.000001) if height <= sea else 0.2 + 0.8 * (height - sea) / maxf(1.0 - sea, 0.000001)

static func _from_working(height: float, sea: float) -> float:
	return height * sea / 0.2 if height <= 0.2 else sea + (height - 0.2) * (1.0 - sea) / 0.8
