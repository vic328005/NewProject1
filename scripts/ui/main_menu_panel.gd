extends Control
class_name MainMenuPanel

const BUTTON_HOVER_SCALE: float = 1.04
const BUTTON_HOVER_DURATION: float = 0.12
const BUTTON_HOVER_WHITE_BLEND: float = 0.35
const BUTTON_HOVER_MODULATE_BOOST: float = 1.5

@onready var start_button: Button = $MenuLayer/MarginContainer/Content/StartButton
@onready var level_button: Button = $MenuLayer/MarginContainer/Content/LevelButton
@onready var load_external_json_button: Button = $MenuLayer/MarginContainer/Content/LoadExternalJsonButton
@onready var status_label: Label = $MenuLayer/MarginContainer/Content/StatusLabel
@onready var quit_button: Button = $MenuLayer/MarginContainer/Content/QuitButton
@onready var level_file_dialog: FileDialog = $LevelFileDialog

var _interactive_buttons: Array[Button] = []
var _button_base_scales: Dictionary = {}
var _button_base_modulates: Dictionary = {}
var _button_base_font_colors: Dictionary = {}
var _button_feedback_tweens: Dictionary = {}
var _button_feedback_strengths: Dictionary = {}


func _ready() -> void:
	assert(start_button != null, "MainMenuPanel requires a StartButton node.")
	assert(level_button != null, "MainMenuPanel requires a LevelButton node.")
	assert(load_external_json_button != null, "MainMenuPanel requires a LoadExternalJsonButton node.")
	assert(status_label != null, "MainMenuPanel requires a StatusLabel node.")
	assert(quit_button != null, "MainMenuPanel requires a QuitButton node.")
	assert(level_file_dialog != null, "MainMenuPanel requires a LevelFileDialog node.")

	_interactive_buttons = [
		start_button,
		level_button,
		quit_button,
		load_external_json_button,
	]
	for button in _interactive_buttons:
		_setup_interactive_button(button)

	start_button.pressed.connect(_on_start_button_pressed)
	level_button.pressed.connect(_on_level_button_pressed)
	load_external_json_button.pressed.connect(_on_load_external_json_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	level_file_dialog.file_selected.connect(_on_level_file_dialog_file_selected)
	level_file_dialog.canceled.connect(_on_level_file_dialog_canceled)

	level_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	level_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	level_file_dialog.title = "选择关卡 JSON"
	level_file_dialog.filters = PackedStringArray(["*.json ; JSON 文件"])

	_set_status_message("")


func _on_start_button_pressed() -> void:
	_set_status_message("")
	if is_instance_valid(GM.audio):
		GM.audio.play_sfx(AudioController.SFX_MENU_START)
	GM.start_game()


func _on_load_external_json_button_pressed() -> void:
	_set_status_message("")
	level_file_dialog.popup_centered()


func _on_level_button_pressed() -> void:
	_set_status_message("")
	if is_instance_valid(GM.audio):
		GM.audio.play_sfx(AudioController.SFX_MENU_START)
	GM.ui.open(UIDef.level_select_panel)


func _on_level_file_dialog_file_selected(path: String) -> void:
	_set_status_message("")
	var result: Dictionary = GM.start_game_from_level_path(path)
	if bool(result.get("success", false)):
		return

	_set_status_message(String(result.get("message", "加载外部 JSON 失败")))


func _on_level_file_dialog_canceled() -> void:
	pass


func _on_quit_button_pressed() -> void:
	var exit_player: AudioStreamPlayer = null
	if is_instance_valid(GM.audio):
		exit_player = GM.audio.play_sfx(AudioController.SFX_MENU_EXIT)
	if is_instance_valid(exit_player):
		await exit_player.finished
	GM.quit_game()


func _set_status_message(message: String) -> void:
	status_label.text = message
	status_label.visible = not message.is_empty()


func _setup_interactive_button(button: Button) -> void:
	var button_id: int = button.get_instance_id()
	_button_base_scales[button_id] = button.scale
	_button_base_modulates[button_id] = button.modulate
	_button_base_font_colors[button_id] = {
		&"font_color": button.get_theme_color(&"font_color"),
		&"font_hover_color": button.get_theme_color(&"font_hover_color"),
		&"font_focus_color": button.get_theme_color(&"font_focus_color"),
	}
	_button_feedback_tweens[button_id] = null
	_button_feedback_strengths[button_id] = 0.0

	_update_button_pivot_offset(button)
	_apply_button_feedback_strength(0.0, button)
	button.mouse_entered.connect(_on_button_hover_started.bind(button))
	button.mouse_exited.connect(_on_button_hover_finished.bind(button))
	button.focus_entered.connect(_on_button_hover_started.bind(button))
	button.focus_exited.connect(_on_button_hover_finished.bind(button))
	button.resized.connect(_on_button_resized.bind(button))


func _on_button_hover_started(button: Button) -> void:
	_play_button_feedback(button, true)


func _on_button_hover_finished(button: Button) -> void:
	if button.is_hovered() or button.has_focus():
		return

	_play_button_feedback(button, false)


func _on_button_resized(button: Button) -> void:
	_update_button_pivot_offset(button)


func _play_button_feedback(button: Button, is_active: bool) -> void:
	var button_id: int = button.get_instance_id()
	var active_tween: Tween = _get_button_feedback_tween(button_id)
	if active_tween != null and active_tween.is_valid():
		active_tween.kill()

	var from_strength: float = _get_button_feedback_strength(button_id)
	var target_strength: float = 1.0 if is_active else 0.0

	var feedback_tween: Tween = create_tween()
	feedback_tween.tween_method(Callable(self, "_apply_button_feedback_strength").bind(button), from_strength, target_strength, BUTTON_HOVER_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	feedback_tween.finished.connect(_on_button_feedback_tween_finished.bind(button_id, feedback_tween), CONNECT_ONE_SHOT)
	_button_feedback_tweens[button_id] = feedback_tween


func _on_button_feedback_tween_finished(button_id: int, finished_tween: Tween) -> void:
	if _get_button_feedback_tween(button_id) != finished_tween:
		return

	_button_feedback_tweens[button_id] = null


func _update_button_pivot_offset(button: Button) -> void:
	button.pivot_offset = button.size * 0.5


func _apply_button_feedback_strength(strength: float, button: Button) -> void:
	var button_id: int = button.get_instance_id()
	_button_feedback_strengths[button_id] = strength

	var base_scale: Vector2 = _get_button_base_scale(button)
	var hover_scale: Vector2 = base_scale * BUTTON_HOVER_SCALE
	button.scale = base_scale.lerp(hover_scale, strength)

	var base_modulate: Color = _get_button_base_modulate(button)
	button.modulate = base_modulate.lerp(_get_button_hover_modulate(base_modulate), strength)

	var base_font_colors: Dictionary = _get_button_base_font_colors(button)
	for color_name_variant in base_font_colors.keys():
		var color_name: StringName = color_name_variant
		var base_color: Color = base_font_colors[color_name]
		var hover_color: Color = _get_button_hover_font_color(base_color)
		button.add_theme_color_override(color_name, base_color.lerp(hover_color, strength))


func _get_button_base_scale(button: Button) -> Vector2:
	var button_id: int = button.get_instance_id()
	if _button_base_scales.has(button_id):
		return _button_base_scales[button_id]

	return button.scale


func _get_button_base_modulate(button: Button) -> Color:
	var button_id: int = button.get_instance_id()
	if _button_base_modulates.has(button_id):
		return _button_base_modulates[button_id]

	return button.modulate


func _get_button_base_font_colors(button: Button) -> Dictionary:
	var button_id: int = button.get_instance_id()
	if _button_base_font_colors.has(button_id):
		return _button_base_font_colors[button_id]

	return {}


func _get_button_feedback_tween(button_id: int) -> Tween:
	if not _button_feedback_tweens.has(button_id):
		return null

	return _button_feedback_tweens[button_id]


func _get_button_feedback_strength(button_id: int) -> float:
	if not _button_feedback_strengths.has(button_id):
		return 0.0

	return _button_feedback_strengths[button_id]


func _get_button_hover_modulate(base_modulate: Color) -> Color:
	return Color(
		base_modulate.r * BUTTON_HOVER_MODULATE_BOOST,
		base_modulate.g * BUTTON_HOVER_MODULATE_BOOST,
		base_modulate.b * BUTTON_HOVER_MODULATE_BOOST,
		base_modulate.a
	)


func _get_button_hover_font_color(base_color: Color) -> Color:
	return Color(
		lerpf(base_color.r, 1.0, BUTTON_HOVER_WHITE_BLEND),
		lerpf(base_color.g, 1.0, BUTTON_HOVER_WHITE_BLEND),
		lerpf(base_color.b, 1.0, BUTTON_HOVER_WHITE_BLEND),
		base_color.a
	)
