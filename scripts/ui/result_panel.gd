extends Control
class_name ResultPanel

const SUCCESS_BANNER_TEXTURE: Texture2D = preload("res://assets/images/success.png")
const FAILED_BANNER_TEXTURE: Texture2D = preload("res://assets/images/failed.png")
const SUCCESS_BUTTON_TEXTURE: Texture2D = preload("res://assets/images/success_button.png")
const FAILED_BUTTON_TEXTURE: Texture2D = preload("res://assets/images/failed_button.png")

const SUCCESS_BUTTON_FONT_COLOR: Color = Color(0.32549, 0.180392, 0.0470588, 1.0)
const SUCCESS_BUTTON_OUTLINE_COLOR: Color = Color(0.933333, 0.878431, 0.682353, 1.0)
const FAILED_BUTTON_FONT_COLOR: Color = Color(0.188235, 0.239216, 0.266667, 1.0)
const FAILED_BUTTON_OUTLINE_COLOR: Color = Color(0.862745, 0.941176, 0.972549, 1.0)

var _is_success_result: bool = false

@onready var banner_rect: TextureRect = $SafeArea/Content/BannerArea/BannerRect
@onready var summary_label: Label = $SafeArea/Content/SummaryCenter/SummaryCard/SummaryLabel
@onready var retry_button: TextureButton = $SafeArea/Content/ButtonsPadding/ButtonsCenter/Buttons/RetryButton
@onready var retry_button_label: Label = $SafeArea/Content/ButtonsPadding/ButtonsCenter/Buttons/RetryButton/Label
@onready var return_button: TextureButton = $SafeArea/Content/ButtonsPadding/ButtonsCenter/Buttons/ReturnButton
@onready var return_button_label: Label = $SafeArea/Content/ButtonsPadding/ButtonsCenter/Buttons/ReturnButton/Label


func _ready() -> void:
	assert(banner_rect != null, "ResultPanel requires a BannerRect node.")
	assert(summary_label != null, "ResultPanel requires a SummaryLabel node.")
	assert(retry_button != null, "ResultPanel requires a RetryButton node.")
	assert(retry_button_label != null, "ResultPanel requires a RetryButton/Label node.")
	assert(return_button != null, "ResultPanel requires a ReturnButton node.")
	assert(return_button_label != null, "ResultPanel requires a ReturnButton/Label node.")

	retry_button.pressed.connect(_on_retry_button_pressed)
	return_button.pressed.connect(_on_return_button_pressed)


func configure(success: bool, shipped_count: int, target_count: int, current_beat: int, beat_limit: int) -> void:
	_is_success_result = success

	if success:
		banner_rect.texture = SUCCESS_BANNER_TEXTURE
		_apply_button_style(SUCCESS_BUTTON_TEXTURE, SUCCESS_BUTTON_FONT_COLOR, SUCCESS_BUTTON_OUTLINE_COLOR)
		_configure_success_actions()
	else:
		banner_rect.texture = FAILED_BANNER_TEXTURE
		_apply_button_style(FAILED_BUTTON_TEXTURE, FAILED_BUTTON_FONT_COLOR, FAILED_BUTTON_OUTLINE_COLOR)
		_configure_failure_actions()

	summary_label.text = "SHIPPED %d / %d\nBEATS %d / %d" % [
		shipped_count,
		target_count,
		current_beat,
		beat_limit,
	]

	if _is_success_result and return_button.visible:
		return_button.grab_focus()
	elif retry_button.visible:
		retry_button.grab_focus()
	else:
		return_button.grab_focus()


func _apply_button_style(texture: Texture2D, font_color: Color, outline_color: Color) -> void:
	_apply_texture_button_texture(retry_button, texture)
	_apply_texture_button_texture(return_button, texture)
	_apply_button_label_style(retry_button_label, font_color, outline_color)
	_apply_button_label_style(return_button_label, font_color, outline_color)


func _apply_texture_button_texture(button: TextureButton, texture: Texture2D) -> void:
	button.texture_normal = texture
	button.texture_hover = texture
	button.texture_pressed = texture
	button.texture_focused = texture
	button.texture_disabled = texture


func _apply_button_label_style(label: Label, font_color: Color, outline_color: Color) -> void:
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", outline_color)


func _configure_success_actions() -> void:
	retry_button_label.text = "MAIN MENU"
	return_button_label.text = "NEXT LEVEL"
	retry_button.visible = true
	return_button.visible = GM.has_next_level()


func _configure_failure_actions() -> void:
	retry_button_label.text = "RETRY LEVEL"
	return_button_label.text = "MAIN MENU"
	retry_button.visible = true
	return_button.visible = true


func _on_retry_button_pressed() -> void:
	if _is_success_result:
		GM.return_to_main_menu()
		return

	GM.restart_current_level()


func _on_return_button_pressed() -> void:
	if _is_success_result:
		if not GM.has_next_level():
			return
		GM.start_next_level()
		return

	GM.return_to_main_menu()
