extends Control
class_name DemoPanel

@onready var message: Label = $Message


func _ready() -> void:
	assert(message != null, "DemoPanel requires a Message label.")
