extends Control
class_name LevelSelectPanel

const LEVEL_BUTTON_TEXT_COLOR: Color = Color(0.858824, 0.760784, 0.909804, 1.0)
const LEVEL_BUTTON_DISABLED_COLOR: Color = Color(0.537255, 0.470588, 0.588235, 0.72)
const LEVEL_BUTTON_HOVER_COLOR: Color = Color(0.988235, 0.866667, 0.988235, 1.0)

@onready var title_label: Label = $Overlay/CenterContainer/Card/MarginContainer/Content/TitleLabel
@onready var level_list: VBoxContainer = $Overlay/CenterContainer/Card/MarginContainer/Content/ScrollContainer/LevelList
@onready var status_label: Label = $Overlay/CenterContainer/Card/MarginContainer/Content/StatusLabel
@onready var return_button: Button = $Overlay/CenterContainer/Card/MarginContainer/Content/ReturnButton

var _first_invalid_message: String = ""


func _ready() -> void:
	assert(title_label != null, "LevelSelectPanel requires a TitleLabel node.")
	assert(level_list != null, "LevelSelectPanel requires a LevelList node.")
	assert(status_label != null, "LevelSelectPanel requires a StatusLabel node.")
	assert(return_button != null, "LevelSelectPanel requires a ReturnButton node.")

	return_button.pressed.connect(_on_return_button_pressed)
	title_label.text = "Select Level"
	_rebuild_level_list()


func _rebuild_level_list() -> void:
	for child_variant in level_list.get_children():
		var child: Node = child_variant as Node
		if child != null:
			child.queue_free()

	_first_invalid_message = ""
	_set_status_message("")

	assert(GM.config != null, "Config must exist before opening LevelSelectPanel.")
	var level_paths: Array[String] = GM.config.selectable_level_paths
	if level_paths.is_empty():
		_set_status_message("No built-in levels are configured yet.")
		return_button.grab_focus()
		return

	var first_enabled_button: Button = null
	for index in range(level_paths.size()):
		var level_path: String = level_paths[index]
		var button: Button = _build_level_button(index, level_path)
		level_list.add_child(button)
		if first_enabled_button == null and not button.disabled:
			first_enabled_button = button

	if first_enabled_button != null:
		first_enabled_button.grab_focus()
		return

	return_button.grab_focus()


func _build_level_button(index: int, level_path: String) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", LEVEL_BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", LEVEL_BUTTON_HOVER_COLOR)
	button.add_theme_color_override("font_focus_color", LEVEL_BUTTON_HOVER_COLOR)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var level_data: LevelData = LevelData.load_from_file(level_path)
	if level_data == null:
		var message: String = LevelData.get_last_error_message()
		if message.is_empty():
			message = "Failed to read level data."
		button.text = "%sUnavailable: %s" % [_build_level_button_prefix(index), level_path.get_file()]
		button.disabled = true
		button.add_theme_color_override("font_color", LEVEL_BUTTON_DISABLED_COLOR)
		_remember_first_invalid_message("%s: %s" % [level_path.get_file(), message])
		_set_status_message(_first_invalid_message)
		return button

	button.text = "%s%s" % [_build_level_button_prefix(index), level_data.display_name]
	button.pressed.connect(_on_level_button_pressed.bind(level_path))
	return button


func _build_level_button_prefix(index: int) -> String:
	return "%02d. " % [index + 1]


func _remember_first_invalid_message(message: String) -> void:
	if _first_invalid_message.is_empty():
		_first_invalid_message = message


func _on_level_button_pressed(level_path: String) -> void:
	_set_status_message("")
	if is_instance_valid(GM.audio):
		GM.audio.play_sfx(AudioController.SFX_MENU_START)

	var result: Dictionary = GM.start_game_from_level_path(level_path)
	if bool(result.get("success", false)):
		return

	_set_status_message(String(result.get("message", "Failed to load level.")))


func _on_return_button_pressed() -> void:
	if is_instance_valid(GM.audio):
		GM.audio.play_sfx(AudioController.SFX_MENU_EXIT)
	queue_free()


func _set_status_message(message: String) -> void:
	status_label.text = message
	status_label.visible = not message.is_empty()
