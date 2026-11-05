extends Node
## Owns the menu and exactly one editor or play session.
const Manifest = preload("res://scripts/storage/world_manifest.gd")
const Document = preload("res://scripts/storage/terrain_document.gd")
const MAPS := "user://maps"
const SETTINGS := "user://display.cfg"

@onready var page: VBoxContainer = $Menu/Center/Page
var session: Node
var files: ItemList
var launch: Button
var message: Label
var preferences := ConfigFile.new()

func _ready() -> void:
	preferences.load(SETTINGS)
	_apply_display()
	_home()

func _page(title: String) -> void:
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 32)
	heading.modulate = Color("#e7d6a3")
	page.add_child(heading)

func _button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 40
	button.pressed.connect(action)
	page.add_child(button)
	return button

func _home() -> void:
	_page("Civilization Legacy")
	_button("Play", _maps).grab_focus()
	_button("Map Editor", _editor)
	_button("Settings", _settings)
	_button("Exit", func(): get_tree().quit())

func _settings() -> void:
	_page("Settings")
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = preferences.get_value("display", "fullscreen", false)
	fullscreen.toggled.connect(func(value: bool):
		preferences.set_value("display", "fullscreen", value)
		_apply_display()
		preferences.save(SETTINGS))
	page.add_child(fullscreen)
	_button("Back", _home)

func _apply_display() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_FULLSCREEN if preferences.get_value("display", "fullscreen", false) else Window.MODE_WINDOWED

func _editor() -> void:
	var editor_world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	editor_world.get_node("Interface/Editor").menu_requested.connect(_leave)
	_enter(editor_world)

func _enter(world: Node) -> void:
	session = world
	$Menu.hide()
	add_child(session)

func _leave() -> void:
	if session == null: return
	remove_child(session)
	session.queue_free()
	session = null
	get_tree().auto_accept_quit = true
	$Menu.show()
	_home()

func _maps() -> void:
	_page("Select a map")
	files = ItemList.new()
	files.custom_minimum_size.y = 200
	page.add_child(files)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(message)
	launch = _button("Play", _play_selected)
	launch.disabled = true
	files.item_selected.connect(func(_index: int):
		launch.disabled = false
		message.text = "")
	files.item_activated.connect(func(_index: int): _play_selected())
	_button("Browse...", _browse)
	_button("Back", _home)
	DirAccess.make_dir_recursive_absolute(MAPS)
	var snapshot := RegEx.new()
	snapshot.compile("-[0-9]+-[0-9]+\\.terrain\\.json$")
	for filename in DirAccess.get_files_at(MAPS):
		if filename.ends_with(".world.json") or (filename.ends_with(".terrain.json") and snapshot.search(filename) == null):
			_add_map(MAPS.path_join(filename))
	if files.item_count == 0:
		message.text = "Save a world in the Map Editor, or browse for an existing map."

func _add_map(path: String) -> int:
	for i in range(files.item_count):
		if files.get_item_metadata(i) == path: return i
	var name_only := path.get_file().trim_suffix(".world.json").trim_suffix(".terrain.json")
	var index := files.add_item(name_only)
	files.set_item_metadata(index, path)
	files.set_item_tooltip(index, path)
	return index

func _browse() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.world.json ; Saved worlds", "*.terrain.json ; Saved terrain maps"])
	dialog.current_dir = ProjectSettings.globalize_path(MAPS)
	page.add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		files.select(_add_map(path))
		launch.disabled = false
		message.text = ""
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.75)

func _play_selected() -> void:
	var selected := files.get_selected_items()
	if selected.is_empty() or session != null: return
	var path: String = files.get_item_metadata(selected[0])
	if path.ends_with(".world.json"):
		var manifest := Manifest.load_file(path)
		if not manifest.error.is_empty():
			message.text = manifest.error
			return
		var snapshot: String = manifest.document.terrain
		path = snapshot if snapshot.is_absolute_path() else path.get_base_dir().path_join(snapshot)
	var loaded := Document.load_file(path)
	if not loaded.ok:
		message.text = loaded.error
		return
	if loaded.document.get("province_layer") == null:
		message.text = "Generate provinces in the Map Editor and save this world before playing."
		return
	var world := (load("res://scenes/gameplay_map.tscn") as PackedScene).instantiate()
	world.menu_session = true
	world.get_node("Terrain").startup_document = loaded.document
	world.return_requested.connect(_leave)
	_enter(world)
	var terrain = world.get_node("Terrain")
	if terrain.province_layer_current():
		for record in terrain.province_layer.records:
			if record.kind == "land" and record.active: return
	_leave()
	_maps()
	message.text = "This world needs current land provinces. Generate them in the Map Editor and save again."
