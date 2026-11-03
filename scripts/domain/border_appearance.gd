extends RefCounted
## Saved presentation choices; loading older documents uses these defaults.
const DEFAULTS = {"province_width":2.4,"nation_width":3.5,"ocean_width":4.5,"distant_scale":0.35,"smooth":true}
static func validate(value: Variant) -> String:
	if not value is Dictionary: return "Invalid border appearance."
	for key in DEFAULTS:
		if key == "smooth":
			if not value.get(key) is bool: return "Invalid border smoothing switch."
			continue
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)): return "Invalid border setting: "+key
		if number < (0.1 if key == "distant_scale" else 0.0) or number > (1.0 if key == "distant_scale" else 12.0): return "Border setting out of range: "+key
	return ""
