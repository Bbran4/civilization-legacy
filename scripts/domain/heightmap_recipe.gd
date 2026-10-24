extends RefCounted
## Native port of the source generator’s integer cell-height operations. See licenses/Heightmap-MIT.txt.
## Geometry is owned by terrain_graph.gd; no regular-grid growth or extra crater.

const PRESETS: Dictionary = {
	"Volcano": "volcano", "High Island": "highIsland", "Low Island": "lowIsland",
	"Continents": "continents", "Archipelago": "archipelago", "Atoll": "atoll",
	"Mediterranean": "mediterranean", "Peninsula": "peninsula", "Pangea": "pangea",
	"Isthmus": "isthmus", "Shattered": "shattered", "Taklamakan": "taklamakan",
	"Old World": "oldWorld", "Fractious": "fractious"
}
const PRECREATED: Dictionary = {
	"World heightmap": "res://data/heightmaps/world.png",
	"Europe heightmap": "res://data/heightmaps/europe.png",
	"Mediterranean heightmap": "res://data/heightmaps/mediterranean-sea.png"
}
const TemplateData = preload("res://data/heightmap_templates.gd")
const Alea = preload("res://scripts/domain/alea.gd")
const BLOB_POWERS: Dictionary = {1000: 0.93, 2000: 0.95, 5000: 0.97, 10000: 0.98, 20000: 0.99, 30000: 0.991, 40000: 0.993, 50000: 0.994, 60000: 0.995, 70000: 0.9955, 80000: 0.996, 90000: 0.9964, 100000: 0.9973}
const LINE_POWERS: Dictionary = {1000: 0.75, 2000: 0.77, 5000: 0.79, 10000: 0.81, 20000: 0.82, 30000: 0.83, 40000: 0.84, 50000: 0.86, 60000: 0.87, 70000: 0.88, 80000: 0.91, 90000: 0.92, 100000: 0.93}
var _graph: RefCounted
var _random: RefCounted
var _heights := PackedByteArray()
var _blob_power: float
var _line_power: float


func generate(graph: RefCounted, preset: String, seed_text: String) -> PackedByteArray:
	_graph = graph
	_random = Alea.new(seed_text) # The source generator resets Alea between graph and recipe.
	_heights.resize(graph.count)
	_heights.fill(0)
	_blob_power = BLOB_POWERS.get(graph.requested_points, 0.98)
	_line_power = LINE_POWERS.get(graph.requested_points, 0.81)
	var recipe: String = TemplateData.RECIPES[PRESETS[preset]]
	for line in recipe.split("\n", false):
		var parts: PackedStringArray = line.strip_edges().split(" ", false)
		match parts[0]:
			"Hill", "Pit", "Range", "Trough":
				var count: int = _random.number(parts[1])
				for i in range(count):
					match parts[0]:
						"Hill": _hill(parts[2], parts[3], parts[4])
						"Pit": _pit(parts[2], parts[3], parts[4])
						_: _range(parts[2], parts[3], parts[4], parts[0] == "Trough")
			"Strait": _strait(parts[1], parts[2])
			"Add", "Multiply": _modify(parts[2], float(parts[1]), parts[0] == "Multiply")
			"Smooth": _smooth(float(parts[1]))
			"Mask": _mask(float(parts[1]))
			"Invert": _invert(float(parts[1]), parts[2])
	graph.heights = _heights
	return _heights


func from_image(graph: RefCounted, source: Image, invert: bool = false) -> PackedByteArray:
	var image: Image = source.duplicate()
	image.resize(graph.columns, graph.rows, Image.INTERPOLATE_BILINEAR)
	var heights := PackedByteArray()
	heights.resize(graph.count)
	for y in range(graph.rows):
		for x in range(graph.columns):
			var lightness: float = clampf(image.get_pixel(x, y).r, 0.0, 1.0)
			if invert:
				lightness = 1.0 - lightness
			var powered: float = lightness if lightness < 0.2 else 0.2 + pow(lightness - 0.2, 0.8)
			heights[y * graph.columns + x] = _limit(floorf(powered * 100.0))
	return heights


func _point_in_range(text: String, length: float) -> float:
	var parts: PackedStringArray = text.split("-")
	var minimum: float = float(parts[0]) / 100.0
	var maximum: float = float(parts[1]) / 100.0 if parts.size() > 1 else minimum
	if maximum == 0.0:
		maximum = minimum
	return _random.integer(minimum * length, maximum * length)


func _start(x_range: String, y_range: String) -> int:
	return _graph.find_cell(_point_in_range(x_range, _graph.map_size.x), _point_in_range(y_range, _graph.map_size.y))


func _hill(height: String, x_range: String, y_range: String) -> void:
	var change := PackedByteArray()
	change.resize(_heights.size())
	var amplitude: int = _limit(_random.number(height))
	var start: int = 0
	for attempt in range(50):
		start = _start(x_range, y_range)
		if _heights[start] + amplitude <= 90:
			break
	change[start] = amplitude
	var queue: Array[int] = [start]
	var cursor: int = 0
	while cursor < queue.size():
		var cell: int = queue[cursor]
		cursor += 1
		for neighbor in _graph.neighbors[cell]:
			if change[neighbor]:
				continue
			change[neighbor] = int(pow(change[cell], _blob_power) * (_random.next() * 0.2 + 0.9)) & 255
			if change[neighbor] > 1:
				queue.append(neighbor)
	for i in range(_heights.size()):
		_heights[i] = _limit(_heights[i] + change[i])


func _pit(height: String, x_range: String, y_range: String) -> void:
	var used := PackedByteArray()
	used.resize(_heights.size())
	var amplitude: float = _limit(_random.number(height))
	var start: int = 0
	for attempt in range(50):
		start = _start(x_range, y_range)
		if _heights[start] >= 20:
			break
	var queue: Array[int] = [start]
	var cursor: int = 0
	while cursor < queue.size():
		var cell: int = queue[cursor]
		cursor += 1
		amplitude = pow(amplitude, _blob_power) * (_random.next() * 0.2 + 0.9)
		if amplitude < 1.0:
			return
		for neighbor in _graph.neighbors[cell]:
			if used[neighbor]:
				continue
			_heights[neighbor] = _limit(_heights[neighbor] - amplitude * (_random.next() * 0.2 + 0.9))
			used[neighbor] = 1
			queue.append(neighbor)


func _path(start: int, target: int, used: PackedByteArray, randomness: float, strait: bool = false) -> Array[int]:
	var path: Array[int] = []
	if not strait:
		path.append(start)
	var current: int = start
	if not strait:
		used[current] = 1
	# Upstream straits do not mark visited cells. Bound repeated visits so a
	# pathological graph/seed cannot hang the editor; normal paths are unchanged.
	var visits := PackedByteArray()
	visits.resize(_heights.size())
	while current != target:
		var best: int = -1
		var best_distance: float = INF
		for neighbor in _graph.neighbors[current]:
			if not strait and used[neighbor]:
				continue
			var dx: float = float(_graph.points[target].x) - float(_graph.points[neighbor].x)
			var dy: float = float(_graph.points[target].y) - float(_graph.points[neighbor].y)
			var distance: float = dx * dx + dy * dy
			if _random.next() > 1.0 - randomness:
				distance /= 2.0
			if distance < best_distance:
				best_distance = distance
				best = neighbor
		if best < 0:
			break
		current = best
		path.append(current)
		if not strait:
			used[current] = 1
		else:
			visits[current] += 1
			if visits[current] == 32:
				push_warning("Strait path stopped after repeated visits to one cell.")
				break
	return path


func _range(height: String, x_range: String, y_range: String, trough: bool) -> void:
	var used := PackedByteArray()
	used.resize(_heights.size())
	var amplitude: float = _limit(_random.number(height))
	var start: int = 0
	var start_x: float = 0.0
	var start_y: float = 0.0
	for attempt in range(50 if trough else 1):
		start_x = _point_in_range(x_range, _graph.map_size.x)
		start_y = _point_in_range(y_range, _graph.map_size.y)
		start = _graph.find_cell(start_x, start_y)
		if not trough or _heights[start] >= 20:
			break
	var end_x: float = 0.0
	var end_y: float = 0.0
	for attempt in range(50):
		end_x = _random.next() * _graph.map_size.x * 0.8 + _graph.map_size.x * 0.1
		end_y = _random.next() * _graph.map_size.y * 0.7 + _graph.map_size.y * 0.15
		var distance: float = absf(end_y - start_y) + absf(end_x - start_x)
		if distance >= _graph.map_size.x / 8.0 and distance <= _graph.map_size.x / (2.0 if trough else 3.0):
			break
	var path: Array[int] = _path(start, _graph.find_cell(end_x, end_y), used, 0.2 if trough else 0.15)
	var queue: Array[int] = path.duplicate()
	var rings: int = 0
	while not queue.is_empty():
		var frontier: Array[int] = queue
		queue = []
		rings += 1
		for cell in frontier:
			var change: float = amplitude * (_random.next() * 0.3 + 0.85)
			_heights[cell] = _limit(_heights[cell] - change if trough else _heights[cell] + change)
		amplitude = pow(amplitude, _line_power) - 1.0
		if amplitude < 2.0:
			break
		for cell in frontier:
			for neighbor in _graph.neighbors[cell]:
				if not used[neighbor]:
					queue.append(neighbor)
					used[neighbor] = 1
	for index in range(0, path.size(), 6):
		var current: int = path[index]
		for i in range(rings):
			var lowest: int = -1
			for neighbor in _graph.neighbors[current]:
				if lowest == -1 or _heights[neighbor] < _heights[lowest]:
					lowest = neighbor
			if lowest < 0:
				continue
			_heights[lowest] = int((_heights[current] * 2.0 + _heights[lowest]) / 3.0)
			current = lowest


func _strait(width_text: String, direction: String) -> void:
	var desired: float = minf(_random.number(width_text), _graph.columns / 3.0)
	if desired < 1.0 and _random.probability(desired):
		return
	if desired <= 0.0:
		return
	var vertical: bool = direction == "vertical"
	var start_x: float = floorf(_random.next() * _graph.map_size.x * 0.4 + _graph.map_size.x * 0.3) if vertical else 5.0
	var start_y: float = 5.0 if vertical else floorf(_random.next() * _graph.map_size.y * 0.4 + _graph.map_size.y * 0.3)
	var end_x: float = floorf(_graph.map_size.x - start_x - _graph.map_size.x * 0.1 + _random.next() * _graph.map_size.x * 0.2) if vertical else _graph.map_size.x - 5.0
	var end_y: float = _graph.map_size.y - 5.0 if vertical else floorf(_graph.map_size.y - start_y - _graph.map_size.y * 0.1 + _random.next() * _graph.map_size.y * 0.2)
	var used := PackedByteArray()
	used.resize(_heights.size())
	var path: Array[int] = _path(_graph.find_cell(start_x, start_y), _graph.find_cell(end_x, end_y), used, 0.2, true)
	var query: Array[int] = []
	var step: float = 0.1 / desired
	for i in range(ceili(desired)):
		var power: float = 0.9 - step * (desired - i)
		for cell in path:
			for neighbor in _graph.neighbors[cell]:
				if used[neighbor]:
					continue
				used[neighbor] = 1
				query.append(neighbor)
				_heights[neighbor] = int(pow(_heights[neighbor], power)) & 255
				if _heights[neighbor] > 100:
					_heights[neighbor] = 5
		path = query.duplicate()


func _modify(height_range: String, value: float, multiply: bool) -> void:
	var minimum: float = 20.0 if height_range == "land" else (0.0 if height_range == "all" else float(height_range.get_slice("-", 0)))
	var maximum: float = 100.0 if height_range in ["land", "all"] else float(height_range.get_slice("-", 1))
	for i in range(_heights.size()):
		var height: float = _heights[i]
		if height < minimum or height > maximum:
			continue
		if multiply:
			height = (height - 20.0) * value + 20.0 if minimum == 20.0 else height * value
		elif value:
			height = maxf(height + value, 20.0) if minimum == 20.0 else height + value
		_heights[i] = _limit(height)


func _smooth(strength: float) -> void:
	var previous: PackedByteArray = _heights.duplicate()
	for i in range(_heights.size()):
		var sum: float = previous[i]
		for neighbor in _graph.neighbors[i]:
			sum += previous[neighbor]
		var mean: float = sum / (_graph.neighbors[i].size() + 1)
		_heights[i] = _limit(mean if strength == 1.0 else (previous[i] * (strength - 1.0) + mean) / strength)


func _mask(power: float) -> void:
	var factor: float = absf(power) if power else 1.0
	for i in range(_heights.size()):
		var x: float = 2.0 * float(_graph.points[i].x) / _graph.map_size.x - 1.0
		var y: float = 2.0 * float(_graph.points[i].y) / _graph.map_size.y - 1.0
		var distance: float = (1.0 - x * x) * (1.0 - y * y)
		if power < 0.0:
			distance = 1.0 - distance
		_heights[i] = _limit((_heights[i] * (factor - 1.0) + _heights[i] * distance) / factor)


func _invert(probability: float, axes: String) -> void:
	if not _random.probability(probability):
		return
	var previous: PackedByteArray = _heights.duplicate()
	for y in range(_graph.rows):
		for x in range(_graph.columns):
			var nx: int = _graph.columns - x - 1 if axes != "y" else x
			var ny: int = _graph.rows - y - 1 if axes != "x" else y
			_heights[y * _graph.columns + x] = previous[ny * _graph.columns + nx]


static func _limit(value: float) -> int:
	return int(clampf(value, 0.0, 100.0))
