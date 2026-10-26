@tool
extends RefCounted
## Bake editable scene geometry into batched meshes, retaining standard colours/textures.
const DEFAULT_CATALOG = preload("res://assets/trees/catalog.tres")
const SHADER = preload("res://scripts/rendering/vegetation.gdshader")
static var meshes: Array[ArrayMesh] = []
static var _catalog: Resource

static func _collect(node: Node, transform: Transform3D, buckets: Dictionary, selected_branch: bool = false) -> void:
	if node is Node3D and not node.visible and not selected_branch:
		return
	if node is Node3D:
		transform = transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface)
			if material != null and not material is StandardMaterial3D:
				push_warning("Tree scene custom shaders require adaptation; use StandardMaterial3D for batched trees.")
			var texture: Texture2D = material.albedo_texture if material is StandardMaterial3D else null
			var roughness: float = material.roughness if material is StandardMaterial3D else 0.95
			var key: String = str(texture.get_instance_id() if texture != null else 0) + ":" + str(roughness)
			if not buckets.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				var shader := ShaderMaterial.new()
				shader.shader = SHADER
				shader.set_shader_parameter("has_albedo_texture", texture != null)
				shader.set_shader_parameter("albedo_texture", texture)
				shader.set_shader_parameter("tree_roughness", roughness)
				tool.set_material(shader)
				buckets[key] = tool
			var tool: SurfaceTool = buckets[key]
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var tint: Color = material.albedo_color if material is StandardMaterial3D else Color.WHITE
			for i in range(indices.size() if not indices.is_empty() else vertices.size()):
				var index: int = indices[i] if not indices.is_empty() else i
				var colour: Color = colours[index] if not colours.is_empty() and (material == null or (material is StandardMaterial3D and material.vertex_color_use_as_albedo)) else Color.WHITE
				tool.set_color(colour * tint)
				tool.set_normal((transform.basis.inverse().transposed() * normals[index]).normalized())
				tool.set_uv(uvs[index] if not uvs.is_empty() else Vector2.ZERO)
				tool.add_vertex(transform * vertices[index])
	for child in node.get_children():
		_collect(child, transform, buckets)

static func ensure_library(catalog: Resource = DEFAULT_CATALOG) -> void:
	if not meshes.is_empty() and _catalog == catalog:
		return
	meshes.clear()
	_catalog = catalog
	for simple in [false, true]:
		for definition in catalog.definitions:
			if definition == null or definition.get("scene") == null:
				meshes.append(ArrayMesh.new())
				continue
			var root: Node = definition.scene.instantiate()
			var branch: Node = root.get_node_or_null("Distant" if simple else "Detailed")
			if branch == null:
				branch = root.get_node_or_null("Detailed")
			if branch == null:
				branch = root
			var buckets: Dictionary = {}
			_collect(branch, root.transform if branch != root and root is Node3D else Transform3D.IDENTITY, buckets, true)
			var mesh := ArrayMesh.new()
			for tool in buckets.values():
				tool.commit(mesh)
			root.free()
			meshes.append(mesh)

static func mesh_for(kind: int, simple: bool) -> ArrayMesh:
	ensure_library(_catalog if _catalog != null else DEFAULT_CATALOG)
	return meshes[kind + (_catalog.definitions.size() if simple else 0)]

static func reload_assets(catalog: Resource) -> Resource:
	if catalog == null:
		return null
	meshes.clear()
	_catalog = null
	if not catalog.resource_path.is_empty():
		return ResourceLoader.load(catalog.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	return catalog
