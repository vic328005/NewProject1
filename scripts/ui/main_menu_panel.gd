extends Control
class_name MainMenuPanel

@onready var start_button: Button = $MenuLayer/MarginContainer/Content/StartButton
@onready var load_external_json_button: Button = $MenuLayer/MarginContainer/Content/LoadExternalJsonButton
@onready var status_label: Label = $MenuLayer/MarginContainer/Content/StatusLabel
@onready var quit_button: Button = $MenuLayer/MarginContainer/Content/QuitButton
@onready var level_file_dialog: FileDialog = $LevelFileDialog


func _ready() -> void:
	assert(start_button != null, "MainMenuPanel requires a StartButton node.")
	assert(load_external_json_button != null, "MainMenuPanel requires a LoadExternalJsonButton node.")
	assert(status_label != null, "MainMenuPanel requires a StatusLabel node.")
	assert(quit_button != null, "MainMenuPanel requires a QuitButton node.")
	assert(level_file_dialog != null, "MainMenuPanel requires a LevelFileDialog node.")

	start_button.pressed.connect(_on_start_button_pressed)
	load_external_json_button.pressed.connect(_on_load_external_json_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	level_file_dialog.file_selected.connect(_on_level_file_dialog_file_selected)
	level_file_dialog.canceled.connect(_on_level_file_dialog_canceled)

	level_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	level_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	level_file_dialog.title = "选择关卡 JSON"
	level_file_dialog.filters = PackedStringArray(["*.json ; JSON 文件"])

	_set_status_message("")
	start_button.grab_focus()


func _on_start_button_pressed() -> void:
	_set_status_message("")
	GM.start_game()


func _on_load_external_json_button_pressed() -> void:
	_set_status_message("")
	level_file_dialog.popup_centered()


func _on_level_file_dialog_file_selected(path: String) -> void:
	_set_status_message("")
	var result: Dictionary = GM.start_game_from_external_level(path)
	if bool(result.get("success", false)):
		return

	_set_status_message(String(result.get("message", "加载外部 JSON 失败")))


func _on_level_file_dialog_canceled() -> void:
	pass


func _on_quit_button_pressed() -> void:
	GM.quit_game()


func _set_status_message(message: String) -> void:
	status_label.text = message
	status_label.visible = not message.is_empty()
