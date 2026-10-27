extends RefCounted
## Derived highland landforms. Source heightmap, drainage and biome identities stay intact.
var broad := FastNoiseLite.new()
var branch := FastNoiseLite.new()
var warp := FastNoiseLite.new()

func _init(seed_value: int) -> void:
	for sampler in [broad, branch, warp]:
		sampler.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		sampler.fractal_octaves = 3
	broad.seed = seed_value
	branch.seed = seed_value ^ 18437
	warp.seed = seed_value ^ 62117
	broad.frequency = 0.065
	branch.frequency = 0.18
	warp.frequency = 0.025

func offset(point: Vector2, height: float) -> float:
	var mountain: float = smoothstep(0.46, 0.78, height)
	if mountain == 0.0:
		return 0.0
	var warped: Vector2 = point + Vector2(warp.get_noise_2d(point.x, point.y), warp.get_noise_2d(point.x + 137, point.y - 71)) * 12.0
	var spine: float = pow(1.0 - absf(broad.get_noise_2d(warped.x, warped.y)), 6.0)
	var ribs: float = pow(1.0 - absf(branch.get_noise_2d(warped.x, warped.y)), 3.0)
	# Continuous ridge spines with branching shoulders, rather than independent round bumps.
	return mountain * (spine * 0.20 + spine * ribs * 0.075 - (1.0 - ribs) * 0.045)
