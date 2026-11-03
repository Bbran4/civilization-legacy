extends RefCounted
## Trace shared raster edges once, preserving which province lies to the left.
var paths: Array[Dictionary] = []
var smooth := true
var _scale := 1.0
func build(ids: PackedInt32Array, size: Vector2i, softened: bool = true) -> void:
	paths.clear()
	var groups: Dictionary = {}
	smooth = softened
	_scale = 12.0 if smooth else 1.0
	var stride := size.x*12+1 if smooth else size.x+1
	if smooth:
		_contours(groups,ids,size,stride)
	else:
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
			if used[i] == 0 and adjacency[edges[i].x].size() != 2: _trace(pair,edges,adjacency,used,i,stride)
		for i in range(edges.size()):
			if used[i] == 0: _trace(pair,edges,adjacency,used,i,stride)
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
	points.append(Vector2(start % stride,start / stride)/_scale)
	while edge >= 0 and used[edge] == 0:
		used[edge] = 1
		var next: int = edges[edge].y
		points.append(Vector2(next % stride,next / stride)/_scale)
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

# Four triangles per mixed 2x2 sample cell. This is also the fill shader's
# categorical reconstruction: shared labels combine barycentric weights.
func _contours(groups: Dictionary,ids: PackedInt32Array,size: Vector2i,stride: int) -> void:
	for y in range(size.y-1):
		for x in range(size.x-1):
			var i := y*size.x+x
			var a := ids[i]
			var b := ids[i+1]
			var c := ids[i+size.x+1]
			var d := ids[i+size.x]
			if a == b and a == c and a == d: continue
			var labels := [a,b,c,d]
			var middle: int = labels.min()
			var best := 0
			for label in labels:
				var count := labels.count(label)
				if count > best or (count == best and label < middle):
					middle = label
					best = count
			var p := Vector2i(x*12+6,y*12+6)
			var corners := [p,p+Vector2i(12,0),p+Vector2i(12,12),p+Vector2i(0,12)]
			var two_pairs: bool = (a == b and c == d and a != c) or (a == c and b == d and a != b) or (a == d and b == c and a != b)
			if two_pairs:
				for j in range(4):
					var next := (j+1)%4
					if labels[j] != labels[next]: _segment(groups,labels[j],labels[next],(corners[j]+corners[next])/2,p+Vector2i(6,6),corners[j],stride)
				continue
			for j in range(4):
				_triangle(groups,[labels[j],labels[(j+1)%4],middle],[corners[j],corners[(j+1)%4],p+Vector2i(6,6)],stride)
func _triangle(groups: Dictionary,labels: Array,points: Array,stride: int) -> void:
	if labels[0] == labels[1] and labels[0] == labels[2]: return
	if labels[0] != labels[1] and labels[0] != labels[2] and labels[1] != labels[2]:
		var center: Vector2i = (points[0]+points[1]+points[2])/3
		for j in range(3):
			var next := (j+1)%3
			_segment(groups,labels[j],labels[next],(points[j]+points[next])/2,center,points[j],stride)
	else:
		var lone := 2 if labels[0] == labels[1] else (0 if labels[1] == labels[2] else 1)
		var next := (lone+1)%3
		var previous := (lone+2)%3
		_segment(groups,labels[lone],labels[next],(points[lone]+points[next])/2,(points[lone]+points[previous])/2,points[lone],stride)
func _segment(groups: Dictionary,a: int,b: int,p: Vector2i,q: Vector2i,inside: Vector2i,stride: int) -> void:
	if Vector2(q-p).cross(Vector2(inside-p)) < 0:
		var swap := p
		p = q
		q = swap
	_edge(groups,a,b,p,q,stride)
