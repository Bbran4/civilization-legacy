extends RefCounted
## Water surfaces use hydraulic elevations above the carved ground, not draped terrain heights.
const SHADER = preload("res://scripts/rendering/inland_water.gdshader")
const MAX_VERTICES := 2000000

static func build(hydrology: RefCounted, size: Vector2i, sea: float, scale: float) -> Dictionary:
	var wet_pixels := 0
	for i in range(hydrology.levels.size()):
		if hydrology.levels[i] >= 0 and hydrology.water.mask_bytes[i * 4 + 3] > 0:
			wet_pixels += 1
	if wet_pixels > MAX_VERTICES:
		return {"error": "Water coverage exceeds the trial mesh budget. Reduce river density/width or map size."}
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var lookup := PackedInt32Array()
	lookup.resize(size.x * size.y)
	lookup.fill(-1)
	var coverage := PackedByteArray()
	coverage.resize(size.x * size.y)
	for i in range(coverage.size()):
		coverage[i] = 255 if hydrology.levels[i] >= 0 and hydrology.water.mask_bytes[i * 4 + 3] > 0 else 0
	for y in range(size.y - 1):
		for x in range(size.x - 1):
			var pixel := y * size.x + x
			var corners := PackedInt32Array([pixel, pixel + 1, pixel + size.x, pixel + size.x + 1])
			if coverage[corners[0]] == 0 and coverage[corners[1]] == 0 and coverage[corners[2]] == 0 and coverage[corners[3]] == 0:
				continue
			for i in range(4):
				var sample := corners[i]
				if lookup[sample] < 0:
					if vertices.size() >= MAX_VERTICES:
						return {"error": "Water geometry exceeds the trial vertex budget. Reduce river density/width or map size."}
					lookup[sample] = vertices.size()
					var point := Vector2i(sample % size.x, sample / size.x)
					var level: float = hydrology.levels[sample]
					if coverage[sample] == 0:
						level = 0.0
						var count := 0
						for dz in range(-1, 2):
							for dx in range(-1, 2):
								var neighbour := point + Vector2i(dx, dz)
								if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= size.x or neighbour.y >= size.y:
									continue
								var n := neighbour.y * size.x + neighbour.x
								if coverage[n] > 0:
									level += hydrology.levels[n]
									count += 1
						level /= maxi(1, count)
					vertices.append(Vector3(point.x, (level - sea + 0.0001) * scale, point.y))
					normals.append(Vector3.UP)
					uvs.append(Vector2(point))
				corners[i] = lookup[sample]
			indices.append_array(PackedInt32Array([corners[0], corners[2], corners[1], corners[1], corners[2], corners[3]]))
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("coverage", ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, coverage)))
	material.set_shader_parameter("map_size", Vector2(size))
	return {"error": "", "mesh": mesh, "material": material, "wet_pixels": wet_pixels}
