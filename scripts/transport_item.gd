extends Node2D
class_name TransportItem

const MOVE_DURATION_RATIO: float = 0.9

var _item_type: String = CargoType.DEFAULT
var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
var _move_tween: Tween
var last_resolved_beat: int = -1
@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_update_visual_state()

	if _world == null:
		_world = GM.world

	if not _is_registered_to_layer:
		_register_to_item_layer()


func _exit_tree() -> void:
	_stop_move_tween()
	_unregister_from_item_layer()


func get_item_type() -> String:
	return _item_type


func is_cargo() -> bool:
	return false


func is_product() -> bool:
	return false


func get_registered_cell() -> Vector2i:
	return _registered_cell


func was_resolved_on_beat(beat_index: int) -> bool:
	return last_resolved_beat == beat_index


func mark_resolved_on_beat(beat_index: int) -> void:
	last_resolved_beat = beat_index


func place_at_cell(world: World, cell: Vector2i) -> void:
	_world = world
	_registered_cell = cell
	_stop_move_tween()
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_world.item_layer.set_cell(_registered_cell, self)
	_is_registered_to_layer = true


func move_to_cell(target_cell: Vector2i) -> bool:
	if _world == null:
		return false

	if not _is_registered_to_layer:
		_register_to_item_layer()

	if not _is_registered_to_layer:
		return false

	if target_cell == _registered_cell:
		return true

	if _world.item_layer.has_cell(target_cell):
		return false

	if _world.item_layer.get_cell(_registered_cell) != self:
		return false

	var target_global_position: Vector2 = _world.to_global(_world.cell_to_world(target_cell))
	_world.item_layer.erase_cell(_registered_cell)
	_world.item_layer.set_cell(target_cell, self)
	_registered_cell = target_cell
	_start_move_to_global_position(target_global_position)
	return true


func begin_parallel_move() -> void:
	if _world == null or not _is_registered_to_layer:
		return

	if _world.item_layer.get_cell(_registered_cell) == self:
		_world.item_layer.erase_cell(_registered_cell)


func complete_parallel_move(target_cell: Vector2i) -> void:
	if _world == null:
		return

	_registered_cell = target_cell
	_world.item_layer.set_cell(target_cell, self)
	_is_registered_to_layer = true
	var target_global_position: Vector2 = _world.to_global(_world.cell_to_world(target_cell))
	_start_move_to_global_position(target_global_position)


func remove_from_world() -> void:
	_stop_move_tween()
	_unregister_from_item_layer()
	queue_free()


func _register_to_item_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.item_layer.set_cell(_registered_cell, self)
	_stop_move_tween()
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_item_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.item_layer.get_cell(_registered_cell) == self:
		_world.item_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func _start_move_to_global_position(target_global_position: Vector2) -> void:
	_stop_move_tween()

	if global_position.is_equal_approx(target_global_position):
		global_position = target_global_position
		return

	var move_duration: float = _get_move_duration_seconds()
	if move_duration <= 0.0:
		global_position = target_global_position
		return

	_move_tween = create_tween()
	var move_tweener: PropertyTweener = _move_tween.tween_property(self, "global_position", target_global_position, move_duration)
	move_tweener.set_trans(Tween.TRANS_LINEAR)
	_move_tween.finished.connect(_on_move_tween_finished)


func _get_move_duration_seconds() -> float:
	if not is_instance_valid(GM.beats):
		return 0.0

	return maxf(GM.beats.get_beat_interval_seconds() * MOVE_DURATION_RATIO, 0.0)


func _stop_move_tween() -> void:
	if not is_instance_valid(_move_tween):
		return

	_move_tween.kill()
	_move_tween = null


func _on_move_tween_finished() -> void:
	_move_tween = null


func _update_visual_state() -> void:
	pass
