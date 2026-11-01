@tool
extends Resource
## One real surface and its independent black/white coverage pattern.
@export var label: String = "Ground"
@export_enum("Grass", "Dry grass", "Soil", "Sand dunes", "Rock", "Snow", "Wet ground") var starter_texture: int = 3
@export var base_color := Color("c8b781")
@export var albedo: Texture2D
@export var normal: Texture2D
@export var coverage: Texture2D
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var albedo_path: String = ""
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var normal_path: String = ""
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var coverage_path: String = ""
@export_enum("Blotches", "Small islands", "Bands") var pattern: int = 0
@export_range(0.25, 128, 0.25) var tile_size: float = 8.0
@export_range(0, 360, 1) var rotation: float = 0.0
@export_range(1, 256, 1) var patch_size: float = 24.0
@export_range(0, 1, 0.01) var amount: float = 1.0
@export_range(0.1, 1, 0.01) var roughness: float = 0.92

func snapshot() -> Dictionary:
	var result := {"label": label, "starter_texture": starter_texture, "base_color": [base_color.r, base_color.g, base_color.b, base_color.a], "pattern": pattern, "tile_size": tile_size, "rotation": rotation, "patch_size": patch_size, "amount": amount, "roughness": roughness}
	for role in ["albedo", "normal", "coverage"]:
		var texture: Texture2D = get(role)
		result[role + "_path"] = get(role + "_path") if texture == null else texture.resource_path
	return result
