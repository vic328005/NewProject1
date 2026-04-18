extends Node2D
class_name Cargo

const MOVE_DURATION_RATIO := 0.9

@export var cargo_type: String = "NORMAL":
	set(value):
		var normalized_value: String = String(value).strip_edges().to_upper()
		cargo_type = normalized_value if not normalized_value.is_empty() else "NORMAL"

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer := false
var _move_tween: Tween


func _ready() -> void:
	_world = GM.current_world
	_register_to_cargo_layer()


func _exit_tree() -> void:
	_stop_move_tween()
	_unregister_from_cargo_layer()


func _register_to_cargo_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.cargo_layer.set_cell(_registered_cell, self)
	_stop_move_tween()
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

	var target_global_position: Vector2 = _world.to_global(_world.cell_to_world(target_cell))
	_world.cargo_layer.erase_cell(_registered_cell)
	_world.cargo_layer.set_cell(target_cell, self)
	_registered_cell = target_cell
	_start_move_to_global_position(target_global_position)
	return true


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
	if not is_instance_valid(GM.beat_conductor):
		return 0.0

	return maxf(GM.beat_conductor.get_beat_interval_seconds() * MOVE_DURATION_RATIO, 0.0)


func _stop_move_tween() -> void:
	if not is_instance_valid(_move_tween):
		return

	_move_tween.kill()
	_move_tween = null


func _on_move_tween_finished() -> void:
	_move_tween = null
