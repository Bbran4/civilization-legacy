extends RefCounted
## Template-scale shapes stay intact; continuous detail belongs to the saved raster.
const Grid = preload("res://scripts/domain/heightmap_grid.gd")

static func refine(source: PackedFloat32Array, size: Vector2i, seed_text: String, coast: float, mountains: float) -> PackedFloat32Array:
	if coast <= 0.0 and mountains <= 0.0:
		return source.duplicate()
	var seed_value := seed_text.hash()
	var warp := _noise(seed_value, 0.012, 3)
	var coast_noise := _noise(seed_value ^ 13789, 0.095, 4)
	var ridge := _noise(seed_value ^ 73129, 0.022, 5)
	var ribs := _noise(seed_value ^ 9817, 0.085, 4)
	var output := PackedFloat32Array()
	output.resize(source.size())
	var extent := Vector2(size - Vector2i.ONE)
	var scale := 1024.0 / maxf(extent.x, extent.y)
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			var point := Vector2(x, y) * scale
			var h := source[i]
			var near_coast := 1.0 - smoothstep(0.015, 0.14, absf(h - 0.2))
			var displacement := Vector2(warp.get_noise_2d(point.x, point.y), warp.get_noise_2d(point.x + 491, point.y - 277))
			var warped := (Vector2(x, y) + displacement * (2.0 + 15.0 * near_coast) * coast / scale) / extent
			h = Grid.sample(source, size, warped)
			h += coast_noise.get_noise_2d(point.x, point.y) * 0.025 * near_coast * coast
			var land := smoothstep(0.23, 0.65, h)
			var p := point + displacement * 35.0
			var spine := pow(1.0 - absf(ridge.get_noise_2d(p.x, p.y)), 5.0)
			var branches := pow(1.0 - absf(ribs.get_noise_2d(p.x, p.y)), 3.0)
			h += land * mountains * (spine * 0.17 + spine * branches * 0.09 - (1.0 - branches) * 0.04)
			output[i] = clampf(h, 0.0, 1.0)
	if mountains > 0.0:
		_erode(output, size, seed_value, mountains)
	return output

static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var sampler := FastNoiseLite.new()
	sampler.seed = seed_value
	sampler.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sampler.frequency = frequency
	sampler.fractal_type = FastNoiseLite.FRACTAL_FBM
	sampler.fractal_octaves = octaves
	return sampler

static func _erode(heights: PackedFloat32Array, size: Vector2i, seed_value: int, strength: float) -> void:
	# Trace rain downhill on a fixed field before cutting shallow convergent valleys.
	# No water bodies, river layer or climate simulation is created by this pass.
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var flow := PackedInt32Array()
	flow.resize(heights.size())
	for drop in range(clampi(heights.size() / 12, 2000, 60000)):
		var x := random.randi_range(1, size.x - 2)
		var y := random.randi_range(1, size.y - 2)
		for step in range(48):
			var i := y * size.x + x
			if heights[i] <= 0.215:
				break
			flow[i] += 1
			var lowest := i
			var steepest := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var next_x := x + dx
					var next_y := y + dy
					if next_x > 0 and next_x < size.x - 1 and next_y > 0 and next_y < size.y - 1:
						var index := next_y * size.x + next_x
						var slope: float = (heights[i] - heights[index]) / (1.41421356 if dx != 0 and dy != 0 else 1.0)
						if slope > steepest:
							steepest = slope
							lowest = index
			if lowest == i:
				break
			x = lowest % size.x
			y = lowest / size.x
	for i in range(heights.size()):
		if flow[i] > 0:
			heights[i] -= minf(log(1.0 + flow[i]) * 0.003, 0.025) * strength * smoothstep(0.22, 0.5, heights[i])
