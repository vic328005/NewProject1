class_name LevelEntityData
extends RefCounted

var id: String = ""
var kind: String = ""
var cell: Vector2i = Vector2i.ZERO
var data: Dictionary = {}


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"x": cell.x,
		"y": cell.y,
		"data": data.duplicate(true),
	}
