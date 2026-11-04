extends SceneTree
const Appearance = preload("res://scripts/domain/border_appearance.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var bad: Dictionary = Appearance.DEFAULTS.duplicate()
	bad.nation_width = NAN
	check(not Appearance.validate(bad).is_empty(),"NaN widths reject.")
	bad = Appearance.DEFAULTS.duplicate()
	bad.smooth = 1
	check(not Appearance.validate(bad).is_empty(),"Smoothing requires a boolean.")
	var world = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var terrain = world.get_node("Terrain")
	terrain.terrain_template = "Noise"
	terrain.map_size = Vector2(16,16)
	root.add_child(world)
	await process_frame
	var seed_document: Dictionary = Document.capture(terrain)
	world.queue_free()
	await process_frame
	world = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	terrain = world.get_node("Terrain")
	terrain.startup_document = seed_document
	root.add_child(world)
	await process_frame
	var editor = world.get_node("Interface/Editor")
	editor._border_controls.province_width.value = 1.8
	editor._border_controls.nation_width.value = 5.0
	editor._border_controls.ocean_width.value = 7.0
	editor._border_controls.distant_scale.value = 20
	editor._border_controls.smooth.button_pressed = false
	await process_frame
	editor._apply_border_appearance()
	print("Applied appearance: ",terrain.border_appearance," status: ",editor._status.text)
	check(terrain.border_appearance.nation_width == 5.0 and terrain.border_appearance.distant_scale == 0.2 and not terrain.border_appearance.smooth and editor.dirty,"Apply reads all controls and dirties the world.")
	var document: Dictionary = Document.capture(terrain)
	check(Document.validate(document).is_empty(),"New appearance document validates.")
	check(Document.apply(terrain,JSON.parse_string(JSON.stringify(document))).is_empty() and terrain.border_appearance.ocean_width == 7.0,"Appearance survives a real document JSON roundtrip.")
	editor._sync_from_terrain()
	check(editor._border_controls.ocean_width.value == 7.0,"Loaded appearance synchronizes controls.")
	document.erase("border_appearance")
	check(Document.apply(terrain,document).is_empty() and terrain.border_appearance == Appearance.DEFAULTS,"Older saves receive defaults instead of the previous world's choices.")
	document.border_appearance = bad
	check(not Document.validate(document).is_empty(),"Invalid saved appearance rejects before apply.")
	world.queue_free()
	await process_frame
	print("Border appearance controls and persistence: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
