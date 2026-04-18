extends Node2D
class_name Recycler

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false


func _ready() -> void:
	_world = GM.world
	_register_to_recycler_layer()


func _exit_tree() -> void:
	_unregister_from_recycler_layer()


func get_registered_cell() -> Vector2i:
	return _registered_cell


func _register_to_recycler_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.recycler_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_recycler_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.recycler_layer.get_cell(_registered_cell) == self:
		_world.recycler_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false
