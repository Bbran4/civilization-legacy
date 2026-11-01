extends Window
## Runtime asset choices; Apply changes presentation without rebuilding the world.
const Sources = preload("res://scripts/rendering/terrain_materials.gd")
var terrain: Node
var editor: Node
var catalog: Resource
var picker: OptionButton
var cards: HBoxContainer
var status: Label
var file_dialog: FileDialog
var _role: String
var _slot: int
var _syncing := false

func configure(target: Node, owner_editor: Node) -> void:
	terrain = target
	editor = owner_editor
	catalog = terrain.surface_catalog.duplicate(true)
	if picker == null:
		_build()
	_show_row(4)

func _label(parent: Node, text: String) -> Label:
	var node := Label.new()
	node.text = text
	parent.add_child(node)
	return node

func _button(parent: Node, text: String, action: Callable, tip: String = "") -> Button:
	var node := Button.new()
	node.text = text
	node.tooltip_text = tip if not tip.is_empty() else "Close this panel without applying further changes."
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func _build() -> void:
	title = "Ground textures and painting"
	size = Vector2i(880, 720)
	min_size = Vector2i(760, 560)
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 9)
	margin.add_child(form)
	_label(form, "Choose a biome, then its textures and black/white coverage patterns.")
	picker = OptionButton.new()
	for index in range(catalog.rows.size()):
		picker.add_item(catalog.rows[index].label)
		picker.set_item_disabled(index, index in [0, 12])
	picker.tooltip_text = "Choose which biome or surface you want to change."
	picker.item_selected.connect(_show_row)
	form.add_child(picker)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(scroll)
	cards = HBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 12)
	scroll.add_child(cards)
	status = _label(form, "Apply changes when ready; painting does not change climate or elevation.")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	form.add_child(actions)
	_button(actions, "Apply textures", _apply, "Update the ground without generating a new map.")
	_button(actions, "Paint this biome mix", _paint.bind(-1), "Use all three textures in this row as your painting brush.")
	_button(actions, "Close", hide)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp; Images"])
	file_dialog.size = Vector2i(820, 560)
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)

func _number(parent: Node, name_text: String, key: String, slot: int, low: float, high: float, step: float, tip: String) -> void:
	_label(parent, name_text)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = catalog.rows[picker.selected].variants[slot].get(key)
	spin.tooltip_text = tip
	spin.value_changed.connect(_set_value.bind(key, slot))
	parent.add_child(spin)

func _show_row(row: int) -> void:
	_syncing = true
	picker.select(row)
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	for slot in range(3):
		var v: Resource = catalog.rows[row].variants[slot]
		var card := VBoxContainer.new()
		card.custom_minimum_size.x = 250
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(card)
		_label(card, "TEXTURE " + str(slot + 1))
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(96, 64)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if v.albedo != null:
			preview.texture = v.albedo
		elif not v.albedo_path.is_empty() and FileAccess.file_exists(v.albedo_path):
			var image := Image.new()
			if image.load(v.albedo_path) == OK:
				preview.texture = ImageTexture.create_from_image(image)
		else:
			var image := Sources.source_albedo[v.starter_texture].duplicate() as Image
			image.convert(Image.FORMAT_RGB8)
			preview.texture = ImageTexture.create_from_image(image)
			preview.modulate = Color(v.base_color.r / 0.73535698, v.base_color.g / 0.73535698, v.base_color.b / 0.73535698)
		card.add_child(preview)
		var starter := OptionButton.new()
		for name_text in ["Grass", "Dry grass", "Soil", "Sand dunes", "Rock", "Snow", "Wet ground"]:
			starter.add_item(name_text)
		starter.select(v.starter_texture)
		starter.tooltip_text = "Choose a built-in texture; this replaces an imported colour image."
		starter.item_selected.connect(_starter.bind(slot))
		card.add_child(starter)
		_label(card, "Starter colour (built-in only)")
		var color := ColorPickerButton.new()
		color.color = v.base_color
		color.text = "Starter colour"
		color.tooltip_text = "Choose the starter texture's colour; imported colour images keep their own colours."
		color.color_changed.connect(_set_value.bind("base_color", slot))
		card.add_child(color)
		for role in ["albedo", "normal", "coverage"]:
			var title_text: String = {"albedo": "Colour image", "normal": "Normal image", "coverage": "Pattern image"}[role]
			_button(card, title_text + "…", _choose_file.bind(role, slot), "Choose an image for this texture; a pattern image uses white for more coverage and black for less.")
			var path: String = v.get(role + "_path")
			var source: Texture2D = v.get(role)
			_label(card, path.get_file() if not path.is_empty() else (source.resource_path.get_file() if source != null else "Built-in"))
			_button(card, "Use built-in " + {"albedo": "colour", "normal": "normal", "coverage": "pattern"}[role], _clear_file.bind(role, slot), "Use the starter asset instead of an imported image for this part of the texture.")
		var pattern := OptionButton.new()
		for name_text in ["Broad blotches", "Small islands", "Bands"]:
			pattern.add_item(name_text)
		pattern.select(v.pattern)
		pattern.tooltip_text = "Choose the shape used to place this texture beside the other two."
		pattern.item_selected.connect(_set_value.bind("pattern", slot))
		card.add_child(pattern)
		_number(card, "Texture repeat size", "tile_size", slot, 0.25, 128, 0.25, "Bigger numbers make the texture pattern look larger on the ground.")
		_number(card, "Pattern repeat size", "patch_size", slot, 1, 256, 1, "Bigger numbers make larger patches of this texture.")
		_number(card, "Rotation (degrees)", "rotation", slot, 0, 360, 1, "Turn the texture and its coverage pattern.")
		_number(card, "Amount", "amount", slot, 0, 1, 0.05, "Choose how often this texture appears in the biome mix; zero turns it off.")
		_number(card, "Roughness", "roughness", slot, 0.1, 1, 0.05, "Higher values make the ground less shiny.")
		_button(card, "Paint this texture", _paint.bind(slot), "Paint just this texture instead of the biome's full mix.")
	_syncing = false

func _set_value(value: Variant, key: String, slot: int) -> void:
	if not _syncing:
		catalog.rows[picker.selected].variants[slot].set(key, int(value) if key == "pattern" else value)

func _starter(index: int, slot: int) -> void:
	var v: Resource = catalog.rows[picker.selected].variants[slot]
	v.starter_texture = index
	v.albedo = null
	v.albedo_path = ""
	_show_row(picker.selected)

func _choose_file(role: String, slot: int) -> void:
	_role = role
	_slot = slot
	file_dialog.title = "Choose " + role + " image"
	file_dialog.popup_centered()

func _file_selected(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		status.text = "That image could not be read. Choose PNG, JPG or WebP."
		return
	var v: Resource = catalog.rows[picker.selected].variants[_slot]
	v.set(_role, null)
	v.set(_role + "_path", path)
	_show_row(picker.selected)
	status.text = "Image selected. Apply textures to update the map."

func _clear_file(role: String, slot: int) -> void:
	var v: Resource = catalog.rows[picker.selected].variants[slot]
	v.set(role, null)
	v.set(role + "_path", "")
	_show_row(picker.selected)

func _apply() -> bool:
	status.text = "Preparing ground textures…"
	await get_tree().process_frame
	var error: String = terrain.apply_surface_catalog(catalog.duplicate(true))
	status.text = "Textures applied. Save terrain to keep the palette and brush strokes." if error.is_empty() else error
	return error.is_empty()

func _paint(slot: int) -> void:
	if await _apply():
		editor._brush.choose(picker.selected, slot)
		hide()
