extends RefCounted
## Priority-flood drainage on the real cell graph, with rainfall-fed reservoirs.
## Derived routing elevations never overwrite the heightmap.
const VERSION: int = 1
const SEA: float = 20.0
const RUNOFF_FRACTION: float = 0.35
const Grid = preload("res://scripts/domain/heightmap_grid.gd")
const Climate = preload("res://scripts/domain/terrain_climate.gd")
var source_hash: String = ""
var bed := PackedFloat64Array()
var filled := PackedFloat64Array()
var downstream := PackedInt32Array()
var ocean := PackedByteArray()
var lake_ids := PackedInt32Array()
var basin_ids := PackedInt32Array()
var river_ids := PackedInt32Array()
var runoff := PackedFloat64Array()
var flow := PackedFloat64Array()
var lakes: Array[Dictionary] = []
var basins: Array[Dictionary] = []
var rivers: Array[Dictionary] = []
var river_threshold: float = 0.0
var total_input: float = 0.0
var total_evaporation: float = 0.0
var total_export: float = 0.0
var topology_ms: float = 0.0
var climate_ms: float = 0.0
var error: String = ""
var _rank := PackedInt32Array()
var _heap: Array = []
var _area := PackedFloat64Array()
var _node := PackedInt32Array()
var _receiver := PackedInt32Array()
var _order := PackedInt32Array()
var _active := PackedByteArray()


func build(graph: RefCounted, geography: RefCounted) -> void:
	var started: int = Time.get_ticks_usec()
	source_hash = geography.source_hash
	error = ""
	var n: int = graph.count
	bed.resize(n)
	filled.resize(n)
	downstream.resize(n)
	downstream.fill(-1)
	ocean.resize(n)
	ocean.fill(0)
	_rank.resize(n)
	_rank.fill(-1)
	_area.resize(n)
	lake_ids.resize(n)
	lake_ids.fill(-1)
	lakes.clear()
	var queue: Array[int] = []
	for cell in range(n):
		bed[cell] = Grid.sample(geography.display_heights, geography.contour_size, graph.points[cell] / graph.map_size) * 100.0
		filled[cell] = bed[cell]
		_area[cell] = graph.cell_area(cell)
		if bed[cell] < SEA and graph.touches_border(cell):
			ocean[cell] = 1
			queue.append(cell)
	var cursor: int = 0
	while cursor < queue.size():
		var cell: int = queue[cursor]
		cursor += 1
		for neighbor in graph.neighbors[cell]:
			if ocean[neighbor] == 0 and bed[neighbor] < SEA:
				ocean[neighbor] = 1
				queue.append(neighbor)
	var seen: PackedByteArray = ocean.duplicate()
	_heap.clear()
	for cell in range(n):
		if ocean[cell] != 0:
			filled[cell] = SEA
			_rank[cell] = 0
			for neighbor in graph.neighbors[cell]:
				if ocean[neighbor] == 0:
					_push([SEA, cell])
					break
		elif graph.touches_border(cell):
			seen[cell] = 1
			_push([bed[cell], cell])
	var rank: int = 1
	while not _heap.is_empty():
		var item: Array = _pop()
		var cell: int = item[1]
		_rank[cell] = rank
		rank += 1
		for neighbor in graph.neighbors[cell]:
			if seen[neighbor] != 0:
				continue
			seen[neighbor] = 1
			filled[neighbor] = maxf(bed[neighbor], filled[cell])
			downstream[neighbor] = cell
			_push([filled[neighbor], neighbor])
	if seen.count(1) != n:
		error = "Some terrain cells have no route to a boundary."
		return
	# Prefer the steepest true descent; flood parents resolve flats without cycles.
	for cell in range(n):
		if ocean[cell] != 0 or downstream[cell] < 0:
			continue
		var best: float = 0.0
		for neighbor in graph.neighbors[cell]:
			var drop: float = filled[cell] - filled[neighbor]
			if drop > 0.00001:
				var slope: float = drop / maxf(0.0001, graph.points[cell].distance_to(graph.points[neighbor]))
				if slope > best:
					best = slope
					downstream[cell] = neighbor
	# Connected depressions at a common spill elevation are reservoir candidates.
	for cell in range(n):
		if ocean[cell] != 0 or lake_ids[cell] >= 0 or filled[cell] - bed[cell] < 0.025:
			continue
		var id: int = lakes.size()
		var members: Array[int] = [cell]
		lake_ids[cell] = id
		var outlet: int = cell
		var area: float = 0.0
		cursor = 0
		while cursor < members.size():
			var member: int = members[cursor]
			cursor += 1
			area += _area[member]
			if _rank[member] < _rank[outlet]:
				outlet = member
			for neighbor in graph.neighbors[member]:
				if lake_ids[neighbor] < 0 and ocean[neighbor] == 0 and filled[neighbor] - bed[neighbor] >= 0.025 and absf(filled[neighbor] - filled[cell]) < 0.00001:
					lake_ids[neighbor] = id
					members.append(neighbor)
		lakes.append({"id": id, "cells": members, "area": area, "level": filled[cell], "spill_cell": outlet, "receiver_cell": downstream[outlet], "active": false, "outlet_cell": -1, "inflow": 0.0, "outflow": 0.0, "evaporation": 0.0})
	_build_nodes(graph)
	topology_ms = (Time.get_ticks_usec() - started) / 1000.0


func _build_nodes(graph: RefCounted) -> void:
	var n: int = graph.count
	_node.resize(n)
	_receiver.resize(n + lakes.size())
	_receiver.fill(-1)
	_active.resize(_receiver.size())
	_active.fill(0)
	var donors := PackedInt32Array()
	donors.resize(_receiver.size())
	for cell in range(n):
		_node[cell] = n + lake_ids[cell] if lake_ids[cell] >= 0 else cell
		_active[_node[cell]] = 1
	for cell in range(n):
		if lake_ids[cell] < 0 and downstream[cell] >= 0:
			_receiver[cell] = _node[downstream[cell]]
	for lake in lakes:
		if lake.receiver_cell >= 0:
			_receiver[n + lake.id] = _node[lake.receiver_cell]
	for node in range(_receiver.size()):
		if _active[node] and _receiver[node] >= 0:
			donors[_receiver[node]] += 1
	var queue: Array[int] = []
	for node in range(_receiver.size()):
		if _active[node] and donors[node] == 0:
			queue.append(node)
	_order.clear()
	var cursor: int = 0
	while cursor < queue.size():
		var node: int = queue[cursor]
		cursor += 1
		_order.append(node)
		var receiver: int = _receiver[node]
		if receiver >= 0:
			donors[receiver] -= 1
			if donors[receiver] == 0:
				queue.append(receiver)
	if _order.size() != _active.count(1):
		error = "Reservoir routing contains a cycle."


func apply_climate(graph: RefCounted, climate: RefCounted) -> void:
	if not error.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	var n: int = graph.count
	runoff.resize(n)
	flow.resize(n)
	var node_flow := PackedFloat64Array()
	node_flow.resize(_receiver.size())
	var evaporation := PackedFloat64Array()
	evaporation.resize(lakes.size())
	total_input = 0.0
	total_evaporation = 0.0
	total_export = 0.0
	for cell in range(n):
		var info: Dictionary = climate.cell_info(graph.points[cell] / graph.map_size)
		runoff[cell] = info.rainfall * _area[cell] * RUNOFF_FRACTION if ocean[cell] == 0 else 0.0
		node_flow[_node[cell]] += runoff[cell]
		total_input += runoff[cell]
		if lake_ids[cell] >= 0:
			evaporation[lake_ids[cell]] += Climate.evaporative_demand(info.temperature) * _area[cell]
	for node in _order:
		var outgoing: float = node_flow[node]
		if node >= n:
			var lake: Dictionary = lakes[node - n]
			lake.inflow = outgoing
			lake.active = outgoing > 0.000001
			lake.evaporation = minf(outgoing, evaporation[lake.id])
			outgoing -= lake.evaporation
			lake.outflow = outgoing
			lake.outlet_cell = lake.spill_cell if outgoing > 0.000001 else -1
			total_evaporation += lake.evaporation
		if _receiver[node] >= 0:
			node_flow[_receiver[node]] += outgoing
		else:
			total_export += outgoing
	for cell in range(n):
		flow[cell] = node_flow[_node[cell]]
	_basins(graph, node_flow)
	_rivers(graph)
	climate_ms = (Time.get_ticks_usec() - started) / 1000.0


func _basins(graph: RefCounted, node_flow: PackedFloat64Array) -> void:
	var n: int = graph.count
	var roots := PackedInt32Array()
	roots.resize(_receiver.size())
	roots.fill(-1)
	for i in range(_order.size() - 1, -1, -1):
		var node: int = _order[i]
		var receiver: int = _receiver[node]
		if node >= n and lakes[node - n].outlet_cell < 0:
			receiver = -1
		roots[node] = roots[receiver] if receiver >= 0 else node
	basin_ids.resize(n)
	basin_ids.fill(-1)
	basins.clear()
	var mapping: Dictionary = {}
	for cell in range(n):
		if ocean[cell]:
			continue
		var root: int = roots[_node[cell]]
		if not mapping.has(root):
			var kind: String = "closed_lake" if root >= n and lakes[root - n].active else ("dry_depression" if root >= n else ("ocean" if ocean[root] else "map_edge"))
			mapping[root] = basins.size()
			basins.append({"id": basins.size(), "kind": kind, "outlet_cell": lakes[root - n].spill_cell if root >= n else root, "area": 0.0, "cell_count": 0, "discharge": 0.0 if root >= n else node_flow[root]})
		var id: int = mapping[root]
		basin_ids[cell] = id
		basins[id].area += _area[cell]
		basins[id].cell_count += 1


func _rivers(graph: RefCounted) -> void:
	var n: int = graph.count
	river_threshold = maxf(0.000001, graph.map_size.x * graph.map_size.y * 0.002 * 600.0 * RUNOFF_FRACTION)
	var eligible := PackedByteArray()
	eligible.resize(n)
	var flux: PackedFloat64Array = flow.duplicate()
	var donors := PackedInt32Array()
	donors.resize(n)
	for cell in range(n):
		if lake_ids[cell] < 0 and ocean[cell] == 0 and flow[cell] >= river_threshold and downstream[cell] >= 0:
			eligible[cell] = 1
	for lake in lakes:
		if lake.outlet_cell >= 0 and lake.outflow >= river_threshold:
			eligible[lake.spill_cell] = 1
			flux[lake.spill_cell] = lake.outflow
	for cell in range(n):
		if eligible[cell] and lake_ids[downstream[cell]] < 0:
			donors[downstream[cell]] += 1
	river_ids.resize(n)
	river_ids.fill(-1)
	rivers.clear()
	for cell in range(n):
		if eligible[cell] == 0 or river_ids[cell] >= 0 or donors[cell] == 1:
			continue
		var path: Array[int] = []
		var current: int = cell
		var id: int = rivers.size()
		while current >= 0 and eligible[current] and river_ids[current] < 0:
			path.append(current)
			river_ids[current] = id
			var next: int = downstream[current]
			if next < 0:
				break
			if lake_ids[next] >= 0 or ocean[next] or donors[next] != 1 or eligible[next] == 0:
				path.append(next)
				break
			current = next
		if path.size() >= 2:
			rivers.append({"id": id, "cells": path, "head_flow": flux[path[0]], "mouth_flow": flux[path[path.size() - 2]], "lake_outlet": lake_ids[path[0]]})


func cell_info(cell: int) -> Dictionary:
	var lake: Dictionary = lakes[lake_ids[cell]] if lake_ids[cell] >= 0 else {}
	var surface: String = "Open water" if ocean[cell] else ("Lake" if not lake.is_empty() and lake.active else ("Dry lake bed" if not lake.is_empty() else "Land"))
	return {"surface_kind": surface, "basin_id": basin_ids[cell], "lake_id": lake_ids[cell], "river_id": river_ids[cell], "drainage_height": filled[cell], "flow_to": downstream[cell], "runoff": runoff[cell], "discharge": flow[cell], "water_depth": maxf(0.0, SEA - bed[cell]) if ocean[cell] else (maxf(0.0, lake.level - bed[cell]) if not lake.is_empty() and lake.active else 0.0), "lake_level": lake.get("level", -1.0), "lake_outlet": lake.get("outlet_cell", -1), "lake_active": lake.get("active", false), "lake_inflow": lake.get("inflow", 0.0), "lake_outflow": lake.get("outflow", 0.0)}


static func _less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


func _push(item: Array) -> void:
	_heap.append(item)
	var index: int = _heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if not _less(item, _heap[parent]):
			break
		_heap[index] = _heap[parent]
		index = parent
	_heap[index] = item


func _pop() -> Array:
	var first: Array = _heap[0]
	var last: Array = _heap.pop_back()
	if not _heap.is_empty():
		var index: int = 0
		while index * 2 + 1 < _heap.size():
			var child: int = index * 2 + 1
			if child + 1 < _heap.size() and _less(_heap[child + 1], _heap[child]):
				child += 1
			if not _less(_heap[child], last):
				break
			_heap[index] = _heap[child]
			index = child
		_heap[index] = last
	return first


func display_field(graph: RefCounted) -> Image:
	var size: Vector2i = Grid.sample_size_for(graph.map_size, 256)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var point: Vector2 = Vector2(x, y) / Vector2(size - Vector2i.ONE) * graph.map_size
			var cell: int = graph.nearest_cell(point)
			var basin: int = basin_ids[cell]
			var colour := Color("285b70") if basin < 0 else Color.from_hsv(fposmod(basin * 0.61803398875, 1.0), 0.42, 0.78)
			# The old ocean plane must not fill enclosed lake basins at sea level.
			colour.a = 0.0 if lake_ids[cell] >= 0 else 1.0
			image.set_pixel(x, y, colour)
	return image


func is_ocean_coast(point: Vector2, graph: RefCounted) -> bool:
	var cell: int = graph.nearest_cell(point)
	if ocean[cell]:
		return true
	for neighbor in graph.neighbors[cell]:
		if ocean[neighbor]:
			return true
	return false
