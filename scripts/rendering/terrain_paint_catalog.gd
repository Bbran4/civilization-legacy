@tool
extends Resource
const VariantAsset = preload("res://scripts/rendering/terrain_paint_variant.gd")
const BiomeAsset = preload("res://scripts/rendering/terrain_biome_paint.gd")
const ROW_COUNT := 19
const SLOTS := 3
const LIMITS := {"starter_texture": [0, 6], "pattern": [0, 2], "tile_size": [0.25, 128], "rotation": [0, 360], "patch_size": [1, 256], "amount": [0, 1], "roughness": [0.1, 1]}
@export var rows: Array[Resource] = []

func snapshot() -> Dictionary:
	var records: Array = []
	for row in rows:
		var variants: Array = []
		for variant in row.variants:
			variants.append(variant.snapshot())
		records.append({"label": row.label, "variants": variants})
	return {"version": 1, "rows": records}

static func validate_data(data: Variant) -> String:
	if not data is Dictionary or data.get("version") != 1 or not data.get("rows") is Array or data.rows.size() != ROW_COUNT:
		return "The ground palette must contain 19 biome/surface rows."
	for row in data.rows:
		if not row is Dictionary or not row.get("label") is String or row.label.length() > 128 or not row.get("variants") is Array or row.variants.size() != SLOTS:
			return "Each ground row needs three texture slots."
		var amount: float = 0.0
		for v in row.variants:
			if not v is Dictionary or not v.get("label") is String or v.label.length() > 128:
				return "A ground texture has an invalid name."
			for key in LIMITS:
				var value: Variant = v.get(key)
				var limits: Array = LIMITS[key]
				if not (value is int or value is float) or not is_finite(value) or value < limits[0] or value > limits[1]:
					return "Invalid ground texture setting: " + key
				if key in ["starter_texture", "pattern"] and value != floor(value):
					return "Ground texture choices must be whole numbers."
			if not v.get("base_color") is Array or v.base_color.size() != 4:
				return "A starter texture colour needs four channels."
			for channel in v.base_color:
				if not (channel is float or channel is int) or not is_finite(channel) or channel < 0 or channel > 1:
					return "Invalid starter texture colour."
			for role in ["albedo", "normal", "coverage"]:
				if not v.get(role + "_path") is String or v[role + "_path"].length() > 4096:
					return "Invalid texture file path."
			amount += v.amount
		if amount <= 0:
			return "Keep at least one texture enabled in every biome."
	return ""

static func from_data(data: Dictionary) -> Resource:
	var catalog: Resource = load("res://scripts/rendering/terrain_paint_catalog.gd").new()
	for record in data.rows:
		var row = BiomeAsset.new()
		row.label = record.label
		for values in record.variants:
			var v = VariantAsset.new()
			for key in ["label", "starter_texture", "base_color", "pattern", "tile_size", "rotation", "patch_size", "amount", "roughness", "albedo_path", "normal_path", "coverage_path"]:
				if key == "base_color":
					v.base_color = Color(values[key][0], values[key][1], values[key][2], values[key][3])
				else:
					v.set(key, values[key])
			row.variants.append(v)
		catalog.rows.append(row)
	return catalog
