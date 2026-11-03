extends RefCounted
const Paths = preload("res://scripts/rendering/province_border_paths.gd")
const Ribbon = preload("res://scripts/rendering/province_border_ribbon.gdshader")
var root: Node3D
var source: RefCounted
var revision := -1
var extent := Vector2.ZERO
func _init(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "SmoothProvinceBorders"
	parent.add_child(root)
func update(layer: RefCounted,world_extent: Vector2,enabled: bool) -> void:
	root.visible = enabled
	if not enabled: return
	if source == layer and revision == layer.border_revision and extent == world_extent: return
	source = layer
	revision = layer.border_revision
	extent = world_extent
	for child in root.get_children():
		child.visible = false
		child.queue_free()
	if layer.border_geometry == null:
		layer.border_geometry = Paths.new()
		layer.border_geometry.build(layer.ids,layer.size)
	var groups: Dictionary = {}
	for path in layer.border_geometry.paths:
		var a: int = path.a
		var b: int = path.b
		var land_a: bool = a > 0 and layer.records[a-1].kind == "land"
		var land_b: bool = b > 0 and layer.records[b-1].kind == "land"
		var owner_a: int = layer.records[a-1].get("nation_id",0) if land_a else 0
		var owner_b: int = layer.records[b-1].get("nation_id",0) if land_b else 0
		var style := 0 if land_a and land_b else 1
		if land_a and land_b and owner_a != owner_b and (owner_a > 0 or owner_b > 0): style = 2
		var key := str(style)
		if not groups.has(key): groups[key] = {"style":style,"vertices":PackedVector3Array(),"uv":PackedVector2Array(),"colors":PackedColorArray()}
		_append(groups[key],path.points,layer.size)
	for key in groups:
		var group: Dictionary = groups[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.vertices
		arrays[Mesh.ARRAY_TEX_UV] = group.uv
		arrays[Mesh.ARRAY_COLOR] = group.colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := ShaderMaterial.new()
		material.shader = Ribbon
		material.set_shader_parameter("border_style",group.style)
		material.set_shader_parameter("width_pixels",3.5 if group.style == 2 else (2.4 if group.style == 0 else 4.5))
		material.set_shader_parameter("dash_length",maxf(extent.x,extent.y)*2.4/1025.0)
		var instance := MeshInstance3D.new()
		instance.name = "Border_" + key.replace("/","_")
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
func _append(group: Dictionary,pixels: PackedVector2Array,size: Vector2i) -> void:
	var points := PackedVector2Array()
	for p in pixels: points.append((p/Vector2(size)-Vector2.ONE*0.5)*extent)
	if points.size() < 2: return
	var closed := points[0].is_equal_approx(points[-1])
	var arcs := PackedFloat32Array([0.0])
	for i in range(1,points.size()): arcs.append(arcs[-1]+points[i].distance_to(points[i-1]))
	var normals := PackedVector2Array()
	for i in range(points.size()-1):
		var tangent := (points[i+1]-points[i]).normalized()
		normals.append(Vector2(-tangent.y,tangent.x))
		for corner in [Vector2i(i,-1),Vector2i(i,1),Vector2i(i+1,-1),Vector2i(i+1,-1),Vector2i(i,1),Vector2i(i+1,1)]:
			_vertex(group,points[corner.x],normals[-1],arcs[corner.x],corner.y)
	# Fill each corner with a bevel; no unbounded miter extrusion at sharp turns.
	for i in range(points.size()-1):
		if i == 0 and not closed: continue
		var before: Vector2 = normals[i-1] if i > 0 else normals[-1]
		var after: Vector2 = normals[i]
		for side in [-1.0,1.0]:
			_vertex(group,points[i],Vector2.ZERO,arcs[i],0.0)
			_vertex(group,points[i],before,arcs[i],side)
			_vertex(group,points[i],after,arcs[i],side)
func _vertex(group: Dictionary,point: Vector2,normal: Vector2,arc: float,side: float) -> void:
	group.vertices.append(Vector3(point.x,0.06,point.y))
	group.uv.append(Vector2(arc,side))
	group.colors.append(Color(normal.x*0.5+0.5,normal.y*0.5+0.5,1.0/3.0,1.0))
