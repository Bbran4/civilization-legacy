extends RefCounted
## Saved visual choices only. Never participates in hydrology or province identity.
const DEFAULTS = {"version":1,"enabled":true,"variation":0,"scale":6.0,"grass_cover":72.0,"rock_angle":35.0,"snow_height":82.0}
const LIMITS = {"variation":[0,2147483647],"scale":[1.0,32.0],"grass_cover":[0.0,100.0],"rock_angle":[15.0,75.0],"snow_height":[35.0,100.0]}
static func legacy_defaults() -> Dictionary:
	var settings := DEFAULTS.duplicate()
	settings.enabled = false
	return settings
static func validate(value: Variant) -> String:
	if not value is Dictionary or not (value.get("version") is int or value.get("version") is float) or value.version != 1 or not value.get("enabled") is bool: return "Invalid terrain texture settings."
	for key in LIMITS:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number < LIMITS[key][0] or number > LIMITS[key][1]: return "Invalid terrain texture setting: "+key
		if key == "variation" and number != floor(number): return "Texture variation must be a whole number."
	return ""
