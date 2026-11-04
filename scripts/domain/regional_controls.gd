extends RefCounted
const Regions = preload("res://scripts/domain/world_regions.gd")
const DEFAULTS = {"warmth":0.0,"moisture":0.0,"variation":0}
const BYTES = Regions.SIZE*Regions.SIZE*4
var settings: Dictionary = DEFAULTS.duplicate()
var overrides := PackedByteArray()
var _field: RefCounted
var _history: Array[Dictionary] = []
func _init() -> void: overrides.resize(BYTES)
static func validate_settings(value: Variant) -> String:
	if not value is Dictionary: return "Missing regional controls."
	for name in DEFAULTS:
		var v: Variant = value.get(name)
		if not (v is int or v is float) or not is_finite(v): return "Invalid regional "+name+"."
		if name == "variation":
			if v != floor(v) or v < 0 or v > 2147483647: return "Regional variation must be a whole number."
		elif v < -50 or v > 50: return "Regional adjustments must be between -50 and 50."
	return ""
func field(seed_text: String) -> RefCounted:
	if _field == null or _field.seed_text != seed_text:
		_field = Regions.new(seed_text,int(settings.variation),settings.warmth,settings.moisture,overrides)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(overrides)
		hash.update(JSON.stringify(settings).to_utf8_buffer())
		_field.key = seed_text+"/"+hash.finish().hex_encode()
	return _field
func _remember() -> void:
	_history.append({"settings":settings.duplicate(),"overrides":overrides.duplicate()})
	if _history.size() > 16: _history.pop_front()
func apply_global(value: Dictionary) -> String:
	var error := validate_settings(value)
	if not error.is_empty(): return error
	if value == settings: return ""
	_remember()
	settings = {"warmth":float(value.warmth),"moisture":float(value.moisture),"variation":int(value.variation)}
	_field = null
	return ""
func apply_selected(seed_text: String, selection: PackedByteArray, adjustments: Dictionary, reset: bool = false) -> String:
	var error := validate_settings(adjustments)
	if not error.is_empty(): return error
	if selection.size() != Regions.SIZE*Regions.SIZE or selection.count(0) == selection.size(): return "Brush an area on the map first."
	var next := overrides.duplicate()
	var current = field(seed_text)
	var natural = Regions.new(seed_text,int(adjustments.variation)) if not reset else null
	for cell in range(selection.size()):
		if selection[cell] == 0: continue
		var i := cell*4
		if reset:
			for channel in range(4): next[i+channel] = 0
			continue
		var target := Vector2(clampf(natural._raw[i]/255.0+adjustments.warmth/100.0,0,1),clampf(natural._raw[i+1]/255.0+adjustments.moisture/100.0,0,1))
		var old := Vector2(current._raw[i],current._raw[i+1])/255.0
		var blended := old.lerp(target,selection[cell]/255.0)
		next[i] = roundi(blended.x*255)
		next[i+1] = roundi(blended.y*255)
		next[i+2] = 0
		next[i+3] = 255
	if next != overrides:
		_remember()
		overrides = next
		_field = null
	return ""
func undo() -> bool:
	if _history.is_empty(): return false
	var old: Dictionary = _history.pop_back()
	settings = old.settings
	overrides = old.overrides
	_field = null
	return true
func snapshot() -> Dictionary:
	return {"version":1,"settings":settings.duplicate(),"overrides":Marshalls.raw_to_base64(overrides)}
static func decode(value: Variant) -> Dictionary:
	var controls = load("res://scripts/domain/regional_controls.gd").new()
	if value == null: return {"error":"","controls":controls}
	if not value is Dictionary or not (value.get("version") is int or value.get("version") is float) or value.version != 1: return {"error":"Invalid regional controls format."}
	var error := validate_settings(value.get("settings"))
	if not error.is_empty(): return {"error":error}
	var encoded: Variant = value.get("overrides")
	if not encoded is String or encoded.length() != 4*ceili(BYTES/3.0): return {"error":"Invalid regional edit size."}
	var data := Marshalls.base64_to_raw(encoded)
	if data.size() != BYTES or Marshalls.raw_to_base64(data) != encoded: return {"error":"Invalid regional edit data."}
	for i in range(0,BYTES,4):
		if data[i+2] != 0 or data[i+3] not in [0,255]: return {"error":"Invalid regional edit channels."}
	controls.settings = {"warmth":float(value.settings.warmth),"moisture":float(value.settings.moisture),"variation":int(value.settings.variation)}
	controls.overrides = data
	return {"error":"","controls":controls}
