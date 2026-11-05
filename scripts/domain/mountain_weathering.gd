extends RefCounted
## Conservative hillslope relaxation. Procedural worlds only; coast samples stay fixed.
static func apply(heights: PackedFloat32Array, size: Vector2i, sea: float, strength: float) -> PackedFloat32Array:
	if strength <= 0:
		return heights
	var result := heights.duplicate()
	var talus := 0.012 * 1024.0 / maxi(size.x, size.y)
	for pass_index in range(2):
		var delta := PackedFloat32Array()
		delta.resize(result.size())
		for y in range(1, size.y - 1):
			for x in range(1, size.x - 1):
				var i := y * size.x + x
				if result[i] <= sea + 0.02:
					continue
				var lowest := i
				for next in [i - 1, i + 1, i - size.x, i + size.x]:
					if result[next] > sea + 0.02 and result[next] < result[lowest]:
						lowest = next
				var amount := maxf(0, result[i] - result[lowest] - talus) * strength * 0.2
				delta[i] -= amount
				delta[lowest] += amount
		for i in range(result.size()):
			result[i] += delta[i]
	return result
