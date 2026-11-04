extends RefCounted
## Automatic generation choices owned here, independent of camera and machine speed.
## Apply only when creating a new map; loading preserves the saved terrain settings.

const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")


static func apply(terrain: Node) -> void:
	var longest: float = maxf(terrain.map_size.x, terrain.map_size.y)
	terrain.auto_density = true
	terrain.graph_points = 10000
	terrain.resolution = clampi(nearest_po2(ceili(longest / 2.0)), 256, 1024)
	terrain.surface_smoothing = 1
	terrain.elevation = 8.0 if terrain.heightmap_texture != null or Recipe.PRECREATED.has(terrain.terrain_template) else 12.0
	terrain.height_offset = 0.0
	terrain.height_contrast = 1.0
	terrain.template_detail = 0.0
	terrain.mountain_strength = 0.0
	terrain.noise_offset = Vector2.ZERO
	var land := FastNoiseLite.new()
	land.seed = 42
	land.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	land.frequency = 0.035
	land.fractal_type = FastNoiseLite.FRACTAL_FBM
	land.fractal_octaves = 4
	land.fractal_gain = 0.5
	land.fractal_lacunarity = 2.0
	terrain.land_noise = land
	var mountains := FastNoiseLite.new()
	mountains.seed = 137
	mountains.frequency = 0.04
	mountains.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	terrain.mountain_noise = mountains
	terrain.image_blend = 1.0
	terrain.invert_image = false
	terrain.island_enabled = terrain.terrain_template == "Noise" and terrain.heightmap_texture == null
	terrain.island_inner_radius = 0.6
	terrain.island_roundness = 2.6
	terrain.show_water = true
	terrain.sea_level = 0.0
	terrain.water_color = Color("285b70")
	if terrain.heightmap_only:
		terrain.auto_density = false
		terrain.graph_points = 20000
		terrain.resolution = 1024
		terrain.show_water = false
