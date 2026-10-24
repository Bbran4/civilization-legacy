extends RefCounted
## One owner for the sampling layout used by rendering, exports and documents.


static func sample_size_for(map_size: Vector2, longest_edge: int) -> Vector2i:
	var scale: float = float(longest_edge) / maxf(map_size.x, map_size.y)
	return Vector2i(maxi(2, roundi(map_size.x * scale)), maxi(2, roundi(map_size.y * scale))) + Vector2i.ONE


static func mesh_from_heights(heights: PackedFloat32Array, size: Vector2i, extent: Vector2, center: Vector2 = Vector2.ZERO, uv_rect: Rect2 = Rect2(0, 0, 1, 1), coarse: PackedFloat32Array = PackedFloat32Array(), coarse_size: Vector2i = Vector2i.ZERO, shared_normals: PackedVector3Array = PackedVector3Array(), parent_normals: PackedVector3Array = PackedVector3Array()) -> ArrayMesh:
	var cells: Vector2i = size - Vector2i.ONE
	var vertices := PackedVector3Array()
	var normals: PackedVector3Array = normals_from_heights(heights, size, extent) if shared_normals.is_empty() else shared_normals
	var uvs := PackedVector2Array()
	vertices.resize(heights.size())
	uvs.resize(heights.size())
	for y in range(size.y):
		for x in range(size.x):
			var index: int = y * size.x + x
			var uv := Vector2(float(x) / cells.x, float(y) / cells.y)
			var point: Vector2 = center + (uv - Vector2(0.5, 0.5)) * extent
			vertices[index] = Vector3(point.x, heights[index], point.y)
			uvs[index] = uv_rect.position + uv * uv_rect.size
	var morph := PackedVector2Array()
	var coarse_normals := PackedColorArray()
	if not coarse.is_empty():
		morph.resize(heights.size())
		coarse_normals.resize(heights.size())
		var parent: PackedVector3Array = normals_from_heights(coarse, coarse_size, extent) if parent_normals.is_empty() else parent_normals
		for y in range(size.y):
			for x in range(size.x):
				var index: int = y * size.x + x
				var uv := Vector2(float(x) / cells.x, float(y) / cells.y)
				morph[index] = Vector2(sample(coarse, coarse_size, uv), 0.0)
				var normal: Vector3 = sample_normal(parent, coarse_size, uv).normalized() * 0.5 + Vector3.ONE * 0.5
				coarse_normals[index] = Color(normal.x, normal.y, normal.z, 1.0)
	var indices := PackedInt32Array()
	indices.resize(cells.x * cells.y * 6)
	var cursor: int = 0
	for y in range(cells.y):
		for x in range(cells.x):
			var a: int = y * size.x + x
			indices[cursor] = a
			indices[cursor + 1] = a + 1
			indices[cursor + 2] = a + size.x
			indices[cursor + 3] = a + 1
			indices[cursor + 4] = a + size.x + 1
			indices[cursor + 5] = a + size.x
			cursor += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	if not coarse.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = morph
		arrays[Mesh.ARRAY_COLOR] = coarse_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func sample(heights: PackedFloat32Array, size: Vector2i, uv: Vector2) -> float:
	var point: Vector2 = uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(size - Vector2i.ONE)
	var x: int = mini(int(point.x), size.x - 2)
	var y: int = mini(int(point.y), size.y - 2)
	var fx: float = point.x - x
	var fy: float = point.y - y
	var a: float = heights[y * size.x + x]
	var b: float = heights[y * size.x + x + 1]
	var c: float = heights[(y + 1) * size.x + x]
	var d: float = heights[(y + 1) * size.x + x + 1]
	return a + (b - a) * fx + (c - a) * fy if fx + fy <= 1.0 else d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fy)


static func normals_from_heights(heights: PackedFloat32Array, size: Vector2i, extent: Vector2) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(heights.size())
	var cells := size - Vector2i.ONE
	var step: Vector2 = extent / Vector2(cells)
	for y in range(size.y):
		for x in range(size.x):
			var left: int = maxi(0, x - 1)
			var right: int = mini(cells.x, x + 1)
			var top: int = maxi(0, y - 1)
			var bottom: int = mini(cells.y, y + 1)
			var dx: float = (heights[y * size.x + right] - heights[y * size.x + left]) / ((right - left) * step.x)
			var dz: float = (heights[bottom * size.x + x] - heights[top * size.x + x]) / ((bottom - top) * step.y)
			result[y * size.x + x] = Vector3(-dx, 1, -dz).normalized()
	return result


static func sample_normal(values: PackedVector3Array, size: Vector2i, uv: Vector2) -> Vector3:
	var point: Vector2 = uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(size - Vector2i.ONE)
	var x: int = mini(int(point.x), size.x - 2)
	var y: int = mini(int(point.y), size.y - 2)
	var fx: float = point.x - x
	var fy: float = point.y - y
	var a: Vector3 = values[y * size.x + x]
	var b: Vector3 = values[y * size.x + x + 1]
	var c: Vector3 = values[(y + 1) * size.x + x]
	var d: Vector3 = values[(y + 1) * size.x + x + 1]
	return a + (b - a) * fx + (c - a) * fy if fx + fy <= 1.0 else d + (c - d) * (1.0 - fx) + (b - d) * (1.0 - fy)
