extends SceneTree
const Provinces = preload("res://scripts/domain/world_provinces.gd")
const Water = preload("res://scripts/domain/terrain_water_layer.gd")
const Surface = preload("res://scripts/domain/terrain_surface.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var size := Vector2i(17,17)
	var base := PackedFloat32Array()
	base.resize(size.x*size.y)
	base.fill(0.6)
	for y in range(17):
		for x in range(17):
			if x == 0 or y == 0 or x == 16 or y == 16: base[y*17+x] = 0.1
	for y in range(4,7):
		for x in range(4,7): base[y*17+x] = 0.1
	var basin := 5*17+5
	var exact_datum := 10*17+10
	base[exact_datum] = 0.2
	var lake := 12*17+5
	base[lake] = 0.1
	var water := Water.new()
	water.mask_size = size
	water.mask_bytes.resize(base.size()*4)
	water.mask_bytes[lake*4+1] = 255
	var original := base.duplicate()
	var surface := Surface.new()
	surface.size = size
	surface.heights = base.duplicate()
	surface.source_hash = "a".repeat(64)
	var layer := Provinces.new()
	check(layer.generate(base,surface,water,4).is_empty(),"Generate land and inland-water provinces")
	var classes := Provinces.classify(base,0.2,water.mask_bytes,size)
	check(classes[basin] == 3 and classes[exact_datum] == 3 and classes[lake] == 0 and classes[0] == 2,"Below/equal-datum enclosed water is distinct from ocean and hydraulic lakes")
	check(layer.ids[basin] > 0 and layer.records[layer.ids[basin]-1].kind == "inland_water","Basin gets a water province")
	check(layer.ids[exact_datum] > 0 and layer.ids[exact_datum] != layer.ids[basin],"Disconnected basin gets its own identity")
	check(layer.ids[lake] == 0 and layer.ids[0] == 0,"Generated lake and ungenerated ocean stay separate")
	check(layer.validate_coverage(base,0.2,water).is_empty(),"New inland coverage validates")
	var restored := Provinces.decode(JSON.parse_string(JSON.stringify(layer.snapshot())))
	check(restored.error.is_empty() and restored.layer.ids == layer.ids and restored.layer.inland_generated,"New kinds and coverage policy round-trip through JSON")
	var basin_id := layer.ids[basin]
	layer.records[basin_id-1].name = "Named inland sea"
	var point_id := layer.ids[exact_datum]
	check(layer.generate_oceans(base,water,4,"coastal_band",8).is_empty(),"Generate coastal sea without overwriting inland water")
	check(layer.ids[basin] == basin_id and layer.ids[exact_datum] == point_id and layer.ids[lake] == 0 and layer.records[basin_id-1].name == "Named inland sea","Ocean pass preserves basin IDs and generated lakes")
	check(layer.validate_coverage(base,0.2,water).is_empty(),"Combined water coverage validates")
	var corrupted := layer.editable_copy()
	corrupted.ids[basin] = 0
	check(not corrupted.validate_coverage(base,0.2,water).is_empty(),"Missing required basin coverage is rejected")
	check(base == original,"Province generation never modifies heights")
	var bad := layer.snapshot()
	bad.inland_generated = false
	check(not Provinces.decode(bad).error.is_empty(),"New water kinds require an explicit coverage declaration")
	print("Inland-water provinces: %d failures" % failures)
	quit(1 if failures else 0)
