extends CanvasLayer
class_name UiModule

@onready var root: Control = $Root


func _ready() -> void:
	assert(root != null, "UiModule requires a Root control.")


func open() -> void:
	visible = true


func close() -> void:
	visible = false
