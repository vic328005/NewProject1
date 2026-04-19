extends Control
class_name ResultPanel

@onready var title_label: Label = $Center/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var summary_label: Label = $Center/PanelContainer/MarginContainer/VBoxContainer/SummaryLabel
@onready var return_button: Button = $Center/PanelContainer/MarginContainer/VBoxContainer/ReturnButton


func _ready() -> void:
	assert(title_label != null, "ResultPanel requires a TitleLabel node.")
	assert(summary_label != null, "ResultPanel requires a SummaryLabel node.")
	assert(return_button != null, "ResultPanel requires a ReturnButton node.")

	return_button.pressed.connect(_on_return_button_pressed)


func configure(success: bool, recycled_count: int, target_count: int, current_beat: int, beat_limit: int) -> void:
	if success:
		title_label.text = "游戏成功"
	else:
		title_label.text = "游戏失败"

	summary_label.text = "已回收 %d / %d\n当前拍数 %d / %d" % [
		recycled_count,
		target_count,
		current_beat,
		beat_limit,
	]
	return_button.text = "返回主菜单"
	return_button.grab_focus()


func _on_return_button_pressed() -> void:
	GM.return_to_main_menu()
