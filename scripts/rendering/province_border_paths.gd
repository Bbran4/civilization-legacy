extends RefCounted
## Trace shared raster edges once, preserving which province lies to the left.
var paths: Array[Dictionary] = []
func build(ids: PackedInt32Array, size: Vector2i) -> void:
	paths.clear()
	var groups: Dictionary = {}
	for y in range(size.y):
		for x in range(size.x):
			var a := ids[y*size.x+x]
			if x+1 < size.x:
				_edge(groups,a,ids[y*size.x+x+1],Vector2i(x+1,y),Vector2i(x+1,y+1),size.x+1)
			if y+1 < size.y:
				_edge(groups,a,ids[(y+1)*size.x+x],Vector2i(x+1,y+1),Vector2i(x,y+1),size.x+1)
	for pair in groups:
		var edges: Array = groups[pair]
		var adjacency: Dictionary = {}
		for i in range(edges.size()):
			for node in [edges[i].x,edges[i].y]:
				if not adjacency.has(node): adjacency[node] = []
				adjacency[node].append(i)
		var used := PackedByteArray()
		used.resize(edges.size())
		for i in range(edges.size()):
			if used[i] == 0 and adjacency[edges[i].x].size() != 2: _trace(pair,edges,adjacency,used,i,size.x+1)
		for i in range(edges.size()):
			if used[i] == 0: _trace(pair,edges,adjacency,used,i,size.x+1)
func _edge(groups: Dictionary,a: int,b: int,p: Vector2i,q: Vector2i,stride: int) -> void:
	if a == b: return
	if a > b:
		var temp := a
		a = b
		b = temp
		var point := p
		p = q
		q = point
	var pair := Vector2i(a,b)
	if not groups.has(pair): groups[pair] = []
	groups[pair].append(Vector2i(p.y*stride+p.x,q.y*stride+q.x))
func _trace(pair: Vector2i,edges: Array,adjacency: Dictionary,used: PackedByteArray,first: int,stride: int) -> void:
	var points := PackedVector2Array()
	var edge := first
	var start: int = edges[first].x
	points.append(Vector2(start % stride,start / stride))
	while edge >= 0 and used[edge] == 0:
		used[edge] = 1
		var next: int = edges[edge].y
		points.append(Vector2(next % stride,next / stride))
		if next == start or adjacency[next].size() != 2: break
		edge = -1
		for candidate in adjacency[next]:
			if used[candidate] == 0 and edges[candidate].x == next:
				edge = candidate
				break
	if points.size() < 2: return
	# Remove only collinear vertices; retain every generated turn exactly.
	points = simplify(points,0.0)
	paths.append({"a":pair.x,"b":pair.y,"points":points})
static func simplify(points: PackedVector2Array,tolerance: float) -> PackedVector2Array:
	if points.size() < 3: return points
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[-1] = 1
	var stack: Array[Vector2i] = [Vector2i(0,points.size()-1)]
	while not stack.is_empty():
		var range_pair: Vector2i = stack.pop_back()
		var a := points[range_pair.x]
		var delta := points[range_pair.y]-a
		var distance := tolerance*tolerance
		var selected := -1
		for i in range(range_pair.x+1,range_pair.y):
			var t := clampf((points[i]-a).dot(delta)/delta.length_squared(),0,1) if delta.length_squared() > 0 else 0.0
			var d := points[i].distance_squared_to(a+delta*t)
			if d > distance:
				distance = d
				selected = i
		if selected >= 0:
			keep[selected] = 1
			stack.append(Vector2i(range_pair.x,selected))
			stack.append(Vector2i(selected,range_pair.y))
	var result := PackedVector2Array()
	for i in range(points.size()):
		if keep[i] != 0: result.append(points[i])
	return result
