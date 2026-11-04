extends RefCounted
## Boundary-connected low water is ocean. Enclosed low-water components covering
## >=1% of the map (minimum 16 samples) are regional seas, not generated lakes.
## Nonzero coverage: 1 boundary ocean, 2 enclosed regional sea.
static func mask(samples: PackedFloat32Array, dimensions: Vector2i, datum: float = 0.2, inclusive: bool = true) -> PackedByteArray:
	datum = PackedFloat32Array([datum])[0]
	var result := PackedByteArray()
	result.resize(samples.size())
	var seen := PackedByteArray()
	seen.resize(samples.size())
	var minimum := maxi(16,ceili(samples.size()*0.01))
	for seed in range(samples.size()):
		if seen[seed] != 0 or not is_finite(samples[seed]) or samples[seed] > datum or (not inclusive and samples[seed] == datum): continue
		var queue := PackedInt32Array([seed])
		seen[seed] = 1
		var boundary := false
		var cursor := 0
		while cursor < queue.size():
			var pixel := queue[cursor]
			cursor += 1
			var x := pixel%dimensions.x
			if pixel < dimensions.x or pixel >= samples.size()-dimensions.x or x == 0 or x == dimensions.x-1: boundary = true
			for next in [pixel-1 if x > 0 else -1,pixel+1 if x < dimensions.x-1 else -1,pixel-dimensions.x,pixel+dimensions.x]:
				if next >= 0 and next < samples.size() and seen[next] == 0 and (samples[next] < datum or (inclusive and samples[next] == datum)):
					seen[next] = 1
					queue.append(next)
		if boundary or queue.size() >= minimum:
			for pixel in queue: result[pixel] = 1 if boundary else 2
	return result
