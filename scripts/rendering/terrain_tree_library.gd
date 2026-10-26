@tool
extends RefCounted
## Original miniature meshes, with shared detailed and simplified versions.
const NAMES := ["Broadleaf", "Conifer", "Dry woodland", "Tropical", "Wetland woodland"]
static var meshes: Array[ArrayMesh] = []

static func _append(tool: SurfaceTool, primitive: PrimitiveMesh, position: Vector3, colour: Color) -> void:
	var arrays: Array = primitive.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(indices.size() if not indices.is_empty() else vertices.size()):
		var index: int = indices[i] if not indices.is_empty() else i
		tool.set_color(colour)
		tool.set_normal(normals[index])
		tool.add_vertex(vertices[index] + position)

static func _crown(tool: SurfaceTool, position: Vector3, radius: float, height: float, colour: Color, simple: bool) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = height
	sphere.radial_segments = 6 if simple else 9
	sphere.rings = 2 if simple else 4
	_append(tool, sphere, position, colour)

static func ensure_library() -> void:
	if not meshes.is_empty():
		return
	for simple in [false, true]:
		for kind in range(NAMES.size()):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.025
			trunk.bottom_radius = 0.05
			trunk.height = 0.55
			trunk.radial_segments = 5
			trunk.rings = 1
			_append(tool, trunk, Vector3(0, 0.275, 0), Color("65503a"))
			if kind == 1:
				for tier in range(1 if simple else 3):
					var cone := CylinderMesh.new()
					cone.top_radius = 0
					cone.bottom_radius = 0.3 - tier * 0.065
					cone.height = 0.72 if simple else 0.48
					cone.radial_segments = 6 if simple else 8
					cone.rings = 1
					_append(tool, cone, Vector3(0, 0.6 + tier * 0.18, 0), Color("365e4b").lightened(tier * 0.04))
			else:
				var colour: Color = [Color("527c42"), Color("365e4b"), Color("809153"), Color("306b40"), Color("5a8059")][kind]
				var height: float = 0.25 if kind == 2 else (0.7 if kind == 4 else 0.55)
				_crown(tool, Vector3(0, 0.7, 0), 0.35 if kind == 3 else 0.3, height, colour, simple)
				if not simple:
					_crown(tool, Vector3(-0.19, 0.58, 0.04), 0.23, height * 0.8, colour.darkened(0.08), false)
					_crown(tool, Vector3(0.16, 0.63, -0.12), 0.24, height * 0.85, colour.lightened(0.06), false)
			meshes.append(tool.commit())

static func mesh_for(kind: int, simple: bool) -> ArrayMesh:
	ensure_library()
	return meshes[kind + (NAMES.size() if simple else 0)]
