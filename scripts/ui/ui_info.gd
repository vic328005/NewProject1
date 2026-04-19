extends RefCounted
class_name UIInfo

var id: StringName
var scene: PackedScene
var layer: int
var open_policy: int


func _init(ui_id: StringName, ui_scene: PackedScene, ui_layer: int, ui_open_policy: int) -> void:
	assert(not String(ui_id).is_empty(), "UIInfo requires a non-empty id.")
	assert(ui_scene != null, "UIInfo requires a valid scene.")

	id = ui_id
	scene = ui_scene
	layer = ui_layer
	open_policy = ui_open_policy
