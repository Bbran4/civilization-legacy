extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	scene.get_node("Terrain").resolution = 255
	root.add_child(scene)
	await process_frame
	var editor = scene.get_node("Interface/Editor")
	var terrain = scene.get_node("Terrain")
	var picker: OptionButton = editor.find_child("ProvinceAppearance",true,false)
	picker.select(1)
	picker.item_selected.emit(1)
	var ok: bool = not terrain.province_fill and not terrain.map_renderer.material.get_shader_parameter("province_fill")
	picker.select(0)
	picker.item_selected.emit(0)
	ok = ok and terrain.province_fill
	scene.queue_free()
	await process_frame
	print("Province border-only view: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
