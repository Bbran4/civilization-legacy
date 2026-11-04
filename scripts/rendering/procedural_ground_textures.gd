extends RefCounted
## Five small seamless albedo tiles, generated once per seed/variation. All maps
## use mipmaps; no world-sized image bake or external texture downloads are needed.
const TILE_SIZE = 128
const PALETTES = {
	"grass":[Color("596d3b"),Color("8e9e60")],
	"earth":[Color("6d573c"),Color("ac9470")],
	"sand":[Color("a89568"),Color("dac99b")],
	"rock":[Color("65665e"),Color("aaa99b")],
	"snow":[Color("c7d8df"),Color("f1f2ec")]
}
var textures: Dictionary = {}
var key := ""
func _init(world_seed: String, variation: int) -> void:
	key = world_seed+"/"+str(variation)
	for kind in PALETTES:
		var noise := FastNoiseLite.new()
		noise.seed = int((key+"/"+kind).hash() & 0x7fffffff)
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.frequency = 0.055
		noise.fractal_octaves = 4
		noise.fractal_gain = 0.55
		var image := Image.create(TILE_SIZE,TILE_SIZE,false,Image.FORMAT_RGBA8)
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				var uv := Vector2(x,y)/TILE_SIZE
				var n := _periodic(noise,Vector2(x,y),uv)*0.5+0.5
				var grain := _grain(x,y,noise.seed)
				var pattern := n*0.8+grain*0.2
				if kind == "grass": pattern = n*0.65+grain*0.2+_grain(x/2,y/6,noise.seed+47)*0.15
				elif kind == "sand": pattern = clampf(n*0.7+grain*0.15+sin(TAU*(uv.y*12+n))*0.075+0.075,0,1)
				elif kind == "rock":
					var seam := absf(sin(TAU*(uv.x*5+uv.y*9+n*1.5)))
					pattern = clampf(pattern*0.85+seam*0.15-(0.12 if seam < 0.12 else 0.0),0,1)
				elif kind == "snow": pattern = n*0.5+grain*0.12+0.25
				var color: Color = PALETTES[kind][0].lerp(PALETTES[kind][1],pattern)
				color.a = n
				image.set_pixel(x,y,color)
		image.generate_mipmaps()
		textures[kind] = ImageTexture.create_from_image(image)
static func _periodic(noise: FastNoiseLite, point: Vector2, uv: Vector2) -> float:
	var blend := Vector2(smoothstep(0,1,uv.x),smoothstep(0,1,uv.y))
	return lerpf(lerpf(noise.get_noise_2d(point.x,point.y),noise.get_noise_2d(point.x-TILE_SIZE,point.y),blend.x),lerpf(noise.get_noise_2d(point.x,point.y-TILE_SIZE),noise.get_noise_2d(point.x-TILE_SIZE,point.y-TILE_SIZE),blend.x),blend.y)
static func _grain(x: int,y: int,seed: int) -> float:
	# Integer arithmetic makes fine grain reproducible and independent of RNG state.
	var value := (x*374761393+y*668265263+seed) & 0x7fffffff
	value = ((value ^ (value >> 13))*1274126177) & 0x7fffffff
	return float(value & 65535)/65535.0
