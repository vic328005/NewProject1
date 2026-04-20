class_name Machine
extends Node2D

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false


func _ready() -> void:
	if not _should_register_to_machine_layer():
		return

	_world = GM.world
	_register_to_machine_layer()


func _exit_tree() -> void:
	if not _should_register_to_machine_layer():
		return

	_unregister_from_machine_layer()


func get_registered_cell() -> Vector2i:
	return _registered_cell


func get_target_cell() -> Vector2i:
	assert(false, "%s must implement get_target_cell()." % get_script().resource_path)
	return _registered_cell


func output(_beat_index: int) -> Dictionary:
	assert(false, "%s must implement output()." % get_script().resource_path)
	return {
		"action": "none",
	}


func input(_item: Item, _beat_index: int) -> String:
	assert(false, "%s must implement input()." % get_script().resource_path)
	return "reject"


func transport(_item: Item, _beat_index: int) -> Dictionary:
	assert(false, "%s must implement transport()." % get_script().resource_path)
	return {
		"action": "block",
	}


func start(_beat_index: int) -> void:
	assert(false, "%s must implement start()." % get_script().resource_path)


func _should_register_to_machine_layer() -> bool:
	return true


func _register_to_machine_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.machine_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_machine_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.machine_layer.get_cell(_registered_cell) == self:
		_world.machine_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false
