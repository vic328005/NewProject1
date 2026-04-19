extends Control
class_name MainMenuPanel

@onready var start_button: Button = $Center/PanelContainer/MarginContainer/VBoxContainer/StartButton
@onready var quit_button: Button = $Center/PanelContainer/MarginContainer/VBoxContainer/QuitButton


func _ready() -> void:
	assert(start_button != null, "MainMenuPanel requires a StartButton node.")
	assert(quit_button != null, "MainMenuPanel requires a QuitButton node.")

	start_button.pressed.connect(_on_start_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

	start_button.grab_focus()


func _on_start_button_pressed() -> void:
	GM.start_game()


func _on_quit_button_pressed() -> void:
	GM.quit_game()
