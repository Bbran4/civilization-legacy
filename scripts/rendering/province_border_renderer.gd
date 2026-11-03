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
		if owner_a != owner_b and (owner_a > 0 or owner_b > 0): style = 2
		var key := "%d/%d/%d" % [style,owner_a if style == 2 else 0,owner_b if style == 2 else 0]
		if not groups.has(key): groups[key] = {"style":style,"a":owner_a,"b":owner_b,"vertices":PackedVector3Array(),"uv":PackedVector2Array(),"colors":PackedColorArray()}
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
		material.set_shader_parameter("width_pixels",8.0 if group.style == 2 else (1.35 if group.style == 0 else 1.2))
		material.set_shader_parameter("dash_length",maxf(extent.x,extent.y)*6.5/1025.0)
		material.set_shader_parameter("side_a",layer.nation_color(group.a))
		material.set_shader_parameter("side_b",layer.nation_color(group.b))
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
	var offsets := PackedVector2Array()
	var miters := PackedFloat32Array()
	var arcs := PackedFloat32Array([0.0])
	for i in range(points.size()):
		var previous := points[i]-points[i-1] if i > 0 else (points[0]-points[-2] if closed else points[1]-points[0])
		var next := points[i+1]-points[i] if i+1 < points.size() else (points[1]-points[0] if closed else previous)
		previous = previous.normalized()
		next = next.normalized()
		var a := Vector2(-previous.y,previous.x)
		var b := Vector2(-next.y,next.x)
		var normal := (a+b).normalized()
		if normal.length_squared() < 0.1: normal = b
		offsets.append(normal)
		miters.append(minf(2.5,1.0/maxf(0.4,normal.dot(b))))
		if i > 0: arcs.append(arcs[-1]+points[i].distance_to(points[i-1]))
	for i in range(points.size()-1):
		for vertex in [Vector2i(i,-1),Vector2i(i,1),Vector2i(i+1,-1),Vector2i(i+1,-1),Vector2i(i,1),Vector2i(i+1,1)]:
			var j: int = vertex.x
			group.vertices.append(Vector3(points[j].x,0.06,points[j].y))
			group.uv.append(Vector2(arcs[j],vertex.y))
			group.colors.append(Color(offsets[j].x*0.5+0.5,offsets[j].y*0.5+0.5,miters[j]/3.0,1))
