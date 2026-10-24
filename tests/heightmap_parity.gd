extends SceneTree
const Graph = preload("res://scripts/domain/terrain_graph.gd")
const Recipe = preload("res://scripts/domain/heightmap_recipe.gd")
const Alea = preload("res://scripts/domain/alea.gd")
var failures: int = 0


func _initialize() -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/reference/heightmap-reference.json"))
	var unicode_random = Alea.new("legacy 🌋")
	for value in reference.unicode_random:
		_check(unicode_random.next() * 4294967296.0 == value, "Alea must match JS UTF-16 seeding.")
	for data in reference.cases:
		var generated = Graph.new()
		generated.generate(Vector2(data.map_size[0], data.map_size[1]), int(data.requested_points), data.seed)
		_check(data.source_points.size() == generated.count, "Site count must match the original graph generator.")
		var expected_points: Array = data.source_points + data.source_boundary
		_check(generated.points.size() == expected_points.size(), "Boundary site count must match the original graph generator.")
		for i in range(mini(expected_points.size(), generated.points.size())):
			_check(absf(float(generated.points[i].x) - float(expected_points[i][0])) < 0.001 and absf(float(generated.points[i].y) - float(expected_points[i][1])) < 0.001, "Current point generation must match original source within float32 precision.")
		# Keep operation comparison independent of triangulator implementation/order.
		var graph = Graph.new()
		graph.restore(data, Vector2(data.map_size[0], data.map_size[1]), int(data.requested_points))
		for cell in range(graph.count):
			_check(PackedInt32Array(graph.neighbors[cell]) == PackedInt32Array(data.neighbors[cell]), "Restored graph must retain the same cyclic neighbor order.")
		var random = Alea.new(data.seed)
		for value in data.random:
			_check(random.next() * 4294967296.0 == value, "Alea must match original JS outputs exactly.")
		for preset in Recipe.PRESETS:
			var actual: PackedByteArray = Recipe.new().generate(graph, preset, data.seed)
			var expected := PackedByteArray(data.results[Recipe.PRESETS[preset]])
			var differences: int = 0
			for i in range(actual.size()):
				if actual[i] != expected[i]:
					differences += 1
			_check(differences == 0, "%s / seed %s: %d of %d source cell heights differ from upstream." % [preset, data.seed, differences, actual.size()])
		print("Compared 14 templates against original JS, seed ", data.seed)
	print("Source cell-height parity: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
