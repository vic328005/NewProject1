extends Node2D
class_name Cargo

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer := false


func _ready() -> void:
	_world = GM.current_world
	_register_to_cargo_layer()


func _exit_tree() -> void:
	_unregister_from_cargo_layer()


func _register_to_cargo_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.cargo_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_cargo_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.cargo_layer.get_cell(_registered_cell) == self:
		_world.cargo_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func get_registered_cell() -> Vector2i:
	return _registered_cell


func move_to_cell(target_cell: Vector2i) -> bool:
	if _world == null:
		return false

	if not _is_registered_to_layer:
		_register_to_cargo_layer()

	if not _is_registered_to_layer:
		return false

	if target_cell == _registered_cell:
		return true

	if _world.cargo_layer.has_cell(target_cell):
		return false

	if _world.cargo_layer.get_cell(_registered_cell) != self:
		return false

	_world.cargo_layer.erase_cell(_registered_cell)
	_world.cargo_layer.set_cell(target_cell, self)
	_registered_cell = target_cell
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	return true
