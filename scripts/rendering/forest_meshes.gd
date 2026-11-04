extends RefCounted
## Original low-poly species meshes, shared by every forest view.
const Species = preload("res://scripts/domain/tree_species.gd")
const MAX_HEIGHT_FACTOR = 1.25
const MAX_WIDTH_FACTOR = 1.15
const BEND = 0.035
const WIND = 0.015
static var _library: Array[ArrayMesh] = []
static func library() -> Array[ArrayMesh]:
	if _library.is_empty():
		for kind in range(Species.NAMES.size()): _library.append(build(kind))
	return _library
static func build(kind: int) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()
	var bark := Color("66503a")
	match kind:
		Species.OAK:
			_branch(arrays,Vector3.ZERO,Vector3(0,0.85,0),0.05,bark)
			_branch(arrays,Vector3(0,0.42,0),Vector3(-0.22,0.77,0.02),0.025,bark)
			_blob(arrays,Vector3(0,0.90,0),Vector3(0.31,0.34,0.29),Color("577341"))
			_blob(arrays,Vector3(-0.21,0.78,0.02),Vector3(0.24,0.26,0.25),Color("4e6c39"))
			_blob(arrays,Vector3(0.19,0.81,0.06),Vector3(0.25,0.28,0.24),Color("627e47"))
		Species.SPRUCE:
			_branch(arrays,Vector3.ZERO,Vector3(0,1.15,0),0.035,bark)
			for i in range(4):
				var cone := CylinderMesh.new()
				cone.top_radius = 0
				cone.bottom_radius = 0.30-i*0.055
				cone.height = 0.56-i*0.065
				cone.radial_segments = 7
				cone.rings = 1
				_append(arrays,cone,Vector3(0,0.53+i*0.25,0),Vector3.ONE,Color("30523f").lightened(i*0.035))
		Species.BIRCH:
			_branch(arrays,Vector3.ZERO,Vector3(0.025,1.30,0),0.027,Color("c6c8ae"))
			for i in range(3):
				_branch(arrays,Vector3(0,i*0.21+0.19,0),Vector3(0,i*0.21+0.22,0),0.028,Color("5a6154"))
			_blob(arrays,Vector3(0.02,1.25,0),Vector3(0.20,0.35,0.19),Color("72984d"))
			_blob(arrays,Vector3(-0.13,1.02,0.02),Vector3(0.19,0.27,0.18),Color("668c43"))
			_blob(arrays,Vector3(0.14,1.08,-0.03),Vector3(0.18,0.28,0.19),Color("7da052"))
		Species.STONE_PINE:
			_branch(arrays,Vector3.ZERO,Vector3(0.02,1.02,0),0.04,bark)
			_branch(arrays,Vector3(0.01,0.67,0),Vector3(-0.25,1.03,0.04),0.025,bark)
			_branch(arrays,Vector3(0.01,0.67,0),Vector3(0.25,1.05,0),0.025,bark)
			_blob(arrays,Vector3(0,1.15,0),Vector3(0.33,0.18,0.29),Color("41683e"))
			_blob(arrays,Vector3(-0.23,1.08,0.02),Vector3(0.25,0.16,0.24),Color("4c7542"))
			_blob(arrays,Vector3(0.23,1.11,0),Vector3(0.25,0.17,0.23),Color("537c47"))
		Species.OLIVE:
			_branch(arrays,Vector3.ZERO,Vector3(-0.10,0.57,0),0.055,Color("76664e"))
			_branch(arrays,Vector3(0,0.14,0),Vector3(0.18,0.65,0.02),0.035,Color("76664e"))
			_blob(arrays,Vector3(-0.17,0.64,0),Vector3(0.25,0.23,0.24),Color("647b52"))
			_blob(arrays,Vector3(0.17,0.71,0.02),Vector3(0.26,0.24,0.24),Color("72885e"))
			_blob(arrays,Vector3(0,0.82,0),Vector3(0.23,0.21,0.22),Color("7b9066"))
		Species.ACACIA:
			_branch(arrays,Vector3.ZERO,Vector3(0.02,0.70,0),0.04,bark)
			_branch(arrays,Vector3(0.01,0.45,0),Vector3(-0.30,0.93,0.02),0.026,bark)
			_branch(arrays,Vector3(0.01,0.48,0),Vector3(0.28,1.0,-0.03),0.024,bark)
			_blob(arrays,Vector3(0.02,1.04,0),Vector3(0.34,0.12,0.30),Color("6c8847"))
			_blob(arrays,Vector3(-0.28,0.97,0.02),Vector3(0.25,0.11,0.24),Color("617e3c"))
			_blob(arrays,Vector3(0.27,1.03,-0.02),Vector3(0.25,0.12,0.24),Color("77924b"))
		Species.PALM:
			_branch(arrays,Vector3.ZERO,Vector3(0.025,0.65,0),0.035,Color("8b7650"))
			_branch(arrays,Vector3(0.025,0.65,0),Vector3(0.12,1.30,0),0.030,Color("8b7650"))
			var root := Vector3(0.12,1.31,0)
			for i in range(8):
				var angle := TAU*i/8.0
				var direction := Vector3(cos(angle),0,sin(angle))
				var side := Vector3(-sin(angle),0,cos(angle))*0.085
				var mid := root+direction*0.28+Vector3.UP*0.13
				var tip := root+direction*0.58-Vector3.UP*0.20
				_triangle(arrays,root,mid+side,tip,Color("487f3e"))
				_triangle(arrays,root,tip,mid-side,Color("5b9145"))
			_blob(arrays,root,Vector3(0.09,0.11,0.09),Color("677347"))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
static func bounds(mesh: ArrayMesh) -> Vector2:
	var box := mesh.get_aabb()
	var radial := Vector2(maxf(absf(box.position.x),absf(box.end.x)),maxf(absf(box.position.z),absf(box.end.z))).length()
	# Shader width/height variation, curved trunk and maximum wind excursion.
	return Vector2(radial*MAX_WIDTH_FACTOR+box.end.y*box.end.y*(BEND+WIND),box.end.y*MAX_HEIGHT_FACTOR)
static func _branch(arrays: Array,a: Vector3,b: Vector3,radius: float,color: Color) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = radius*0.55
	trunk.bottom_radius = radius
	trunk.height = a.distance_to(b)
	trunk.radial_segments = 5
	trunk.rings = 1
	_append(arrays,trunk,(a+b)*0.5,Vector3.ONE,color,Basis(Quaternion(Vector3.UP,(b-a).normalized())))
static func _blob(arrays: Array,position: Vector3,radii: Vector3,color: Color) -> void:
	var crown := SphereMesh.new()
	crown.radius = 1
	crown.height = 2
	crown.radial_segments = 7
	crown.rings = 2
	_append(arrays,crown,position,radii,color)
static func _triangle(arrays: Array,a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	# Solid geometry on both faces, so palm leaves cast and receive shadows.
	for face in [[a,b,c],[c,b,a]]:
		var normal: Vector3 = (face[1]-face[0]).cross(face[2]-face[0]).normalized()
		for vertex in face:
			arrays[Mesh.ARRAY_INDEX].append(arrays[Mesh.ARRAY_VERTEX].size())
			arrays[Mesh.ARRAY_VERTEX].append(vertex)
			arrays[Mesh.ARRAY_NORMAL].append(normal)
			arrays[Mesh.ARRAY_COLOR].append(color)
static func _append(target: Array,mesh: PrimitiveMesh,position: Vector3,scale: Vector3,color: Color,rotation: Basis = Basis.IDENTITY) -> void:
	var source := mesh.get_mesh_arrays()
	var base: int = target[Mesh.ARRAY_VERTEX].size()
	for vertex in source[Mesh.ARRAY_VERTEX]:
		var point: Vector3 = rotation*(vertex*scale)+position
		point.y = maxf(0.0,point.y)
		target[Mesh.ARRAY_VERTEX].append(point)
	for normal in source[Mesh.ARRAY_NORMAL]: target[Mesh.ARRAY_NORMAL].append((rotation*(normal/scale)).normalized())
	for _vertex in source[Mesh.ARRAY_VERTEX]: target[Mesh.ARRAY_COLOR].append(color)
	for index in source[Mesh.ARRAY_INDEX]: target[Mesh.ARRAY_INDEX].append(base+index)
