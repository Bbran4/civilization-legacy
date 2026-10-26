@tool
extends Resource
## Editable scene and habitat rules for one decorative tree family.
@export var label: String = "Tree"
@export var scene: PackedScene
@export_flags("Marine", "Ice", "Tundra", "Cold desert", "Hot desert", "Steppe", "Grassland", "Savanna", "Boreal forest", "Temperate forest", "Temperate rainforest", "Tropical rainforest", "Lake", "Wetland", "Riparian woodland") var biome_mask: int = 0
@export_range(0, 1, 0.01) var canopy_floor: float = 0.0
@export_range(0.05, 4, 0.01) var footprint_radius: float = 0.43
@export_range(0.1, 3, 0.05) var maximum_slope: float = 0.85
@export_range(-80, 60, 1) var minimum_temperature: float = -80
@export_range(-80, 60, 1) var maximum_temperature: float = 60
