extends RefCounted
## Small original meshes, shared by all instances; no external tree assets.
static func build(conifer: bool) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.027
	trunk.bottom_radius = 0.045
	trunk.height = 0.65
	trunk.radial_segments = 6
	_append(arrays,trunk,Vector3(0,0.325,0),Vector3.ONE,Color("66503a"))
	if conifer:
		for i in range(3):
			var crown := CylinderMesh.new()
			crown.top_radius = 0
			crown.bottom_radius = 0.28-i*0.065
			crown.height = 0.55-i*0.07
			crown.radial_segments = 7
			_append(arrays,crown,Vector3(0,0.55+i*0.23,0),Vector3.ONE,Color("35533e").lightened(i*0.045))
	else:
		for entry in [[Vector3(0,0.83,0),Vector3(1.0,1.15,1.0)],[Vector3(-0.15,0.66,0.03),Vector3(0.73,0.8,0.78)],[Vector3(0.15,0.73,0.04),Vector3(0.72,0.85,0.75)]]:
			var crown := SphereMesh.new()
			crown.radius = 0.27
			crown.height = 0.54
			crown.radial_segments = 8
			crown.rings = 3
			_append(arrays,crown,entry[0],entry[1],Color("577341"))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
static func _append(target: Array,mesh: PrimitiveMesh,position: Vector3,scale: Vector3,color: Color) -> void:
	var source := mesh.get_mesh_arrays()
	var base: int = target[Mesh.ARRAY_VERTEX].size()
	for vertex in source[Mesh.ARRAY_VERTEX]: target[Mesh.ARRAY_VERTEX].append(vertex*scale+position)
	for normal in source[Mesh.ARRAY_NORMAL]: target[Mesh.ARRAY_NORMAL].append((normal/scale).normalized())
	for _vertex in source[Mesh.ARRAY_VERTEX]: target[Mesh.ARRAY_COLOR].append(color)
	for index in source[Mesh.ARRAY_INDEX]: target[Mesh.ARRAY_INDEX].append(base+index)
