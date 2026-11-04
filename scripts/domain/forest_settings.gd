extends RefCounted
const DEFAULTS = {"version":1,"enabled":true,"variation":0,"count":5000,"coverage":60.0,"size":1.0,"max_slope":32.0,"tree_line":78.0}
const LIMITS = {"variation":[0,2147483647],"count":[0,20000],"coverage":[0,100],"size":[0.4,2.0],"max_slope":[10,55],"tree_line":[45,95]}
static func legacy_defaults() -> Dictionary:
	var value := DEFAULTS.duplicate()
	value.enabled = false
	return value
static func validate(value: Variant) -> String:
	if not value is Dictionary or not (value.get("version") is int or value.get("version") is float) or value.version != 1 or not value.get("enabled") is bool: return "Invalid tree settings."
	for key in LIMITS:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number < LIMITS[key][0] or number > LIMITS[key][1]: return "Invalid tree setting: "+key
		if key in ["variation","count"] and number != floor(number): return "Tree budget and variation must be whole numbers."
	return ""
