extends SceneTree
## Regenerate the graph inputs for the independent upstream JS comparison.
const Graph = preload("res://scripts/domain/terrain_graph.gd")


func _initialize() -> void:
	var cases: Array = []
	for specification in [["42", 1000], ["brenden-legacy", 1000], ["42", 10000]]:
		var seed_text: String = specification[0]
		var desired: int = specification[1]
		var graph = Graph.new()
		graph.generate(Vector2(1536, 768), desired, seed_text)
		var data: Dictionary = graph.snapshot()
		data["neighbors"] = graph.neighbors
		data["seed"] = seed_text
		data["map_size"] = [1536, 768]
		data["requested_points"] = desired
		cases.append(data)
	var file := FileAccess.open("res://tests/reference/graph-inputs.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(cases, "", true, true))
	file.close()
	print("Exported three production Voronoi graphs for upstream comparison.")
	quit()
