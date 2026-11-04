extends RefCounted
## Stylized regional species mixes, not a botanical/climate simulation.
const OAK = 0
const SPRUCE = 1
const BIRCH = 2
const STONE_PINE = 3
const OLIVE = 4
const ACACIA = 5
const PALM = 6
const NAMES = ["Oak","Spruce","Birch","Stone pine","Olive","Acacia","Palm"]
static func choose(region: Vector2, height: float, roll: float) -> int:
	var cold := 1.0-smoothstep(0.25,0.60,region.x)
	var hot := smoothstep(0.62,0.86,region.x)
	var wet := smoothstep(0.25,0.75,region.y)
	var mild := maxf(0.0,1.0-absf(region.x-0.50)*2.0)
	var weights := PackedFloat32Array([
		(1.0-cold)*(1.0-hot)*wet*0.9+0.025,
		cold*0.9+smoothstep(0.5,0.75,height)*(1.0-hot)*0.35+0.015,
		(1.0-hot)*wet*(0.35+0.65*cold)*0.7,
		(1.0-cold)*(1.0-wet)*(0.7-0.3*hot),
		(1.0-cold)*mild*(1.0-hot*0.5)*(1.0-wet)*0.9,
		hot*(1.0-wet)*1.8,
		hot*wet*1.8])
	var total := 0.0
	for weight in weights: total += weight
	var target := clampf(roll,0.0,0.999999)*total
	for i in range(weights.size()):
		target -= weights[i]
		if target < 0: return i
	return OAK
