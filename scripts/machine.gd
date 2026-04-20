class_name Machine
extends Node2D

const SIGNAL_FEEDBACK_DURATION: float = 0.18
const SIGNAL_FEEDBACK_SCALE_BONUS: float = 0.05

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
var _signal_feedback_base_scale: Vector2 = Vector2.ONE
var _signal_feedback_time_left: float = 0.0
var _last_signal_feedback_beat_index: int = -1
var _signal_feedback_scale_target: Node2D


func _ready() -> void:
	_signal_feedback_scale_target = _get_signal_feedback_scale_target()
	if _signal_feedback_scale_target == null:
		_signal_feedback_scale_target = self

	_signal_feedback_base_scale = _signal_feedback_scale_target.scale
	_apply_signal_feedback_visuals(0.0)
	set_process(false)

	if not _should_register_to_machine_layer():
		return

	_world = GM.world
	_register_to_machine_layer()


func _process(delta: float) -> void:
	if _signal_feedback_time_left <= 0.0:
		_reset_signal_feedback()
		return

	_signal_feedback_time_left = maxf(_signal_feedback_time_left - delta, 0.0)
	_apply_signal_feedback_state()
	if _signal_feedback_time_left <= 0.0:
		_reset_signal_feedback()


func _exit_tree() -> void:
	_reset_signal_feedback()
	if not _should_register_to_machine_layer():
		return

	_unregister_from_machine_layer()


func get_registered_cell() -> Vector2i:
	return _registered_cell


func get_target_cell() -> Vector2i:
	assert(false, "%s must implement get_target_cell()." % get_script().resource_path)
	return _registered_cell


func plan_output(_beat_index: int, _receives_signal: bool) -> Dictionary:
	assert(false, "%s must implement plan_output()." % get_script().resource_path)
	return {
		"action": "none",
	}


func plan_transport(_item: Item, _beat_index: int, _receives_signal: bool) -> Dictionary:
	assert(false, "%s must implement plan_transport()." % get_script().resource_path)
	return {
		"action": "block",
	}


func plan_input(_item: Item, _beat_index: int, _receives_signal: bool) -> Dictionary:
	assert(false, "%s must implement plan_input()." % get_script().resource_path)
	return {
		"action": "reject",
	}


func trigger_signal_feedback(beat_index: int) -> void:
	if beat_index == _last_signal_feedback_beat_index and _signal_feedback_time_left > 0.0:
		return

	_last_signal_feedback_beat_index = beat_index
	_signal_feedback_time_left = SIGNAL_FEEDBACK_DURATION
	_apply_signal_feedback_state()
	set_process(true)


func _should_register_to_machine_layer() -> bool:
	return true


func _apply_signal_feedback_state() -> void:
	var strength: float = _get_signal_feedback_strength()
	var flash_strength: float = _get_signal_feedback_flash_strength()
	_signal_feedback_scale_target.scale = _signal_feedback_base_scale * (1.0 + _get_signal_feedback_scale_bonus())
	_apply_signal_feedback_visuals(flash_strength)


func _get_signal_feedback_strength() -> float:
	if SIGNAL_FEEDBACK_DURATION <= 0.0:
		return 0.0

	return clampf(_signal_feedback_time_left / SIGNAL_FEEDBACK_DURATION, 0.0, 1.0)


func _get_signal_feedback_scale_bonus() -> float:
	var strength: float = _get_signal_feedback_flash_strength()
	if strength <= 0.0:
		return 0.0

	return SIGNAL_FEEDBACK_SCALE_BONUS * strength


func _get_signal_feedback_flash_strength() -> float:
	var strength: float = _get_signal_feedback_strength()
	if strength <= 0.0:
		return 0.0

	var progress: float = 1.0 - strength
	var envelope: float = pow(strength, 1.35)
	var pulse: float = pow(absf(cos(progress * PI * 2.0)), 1.6)
	# 一次触发内闪两下：起手更亮，半拍后再补一次稍弱的白闪。
	return envelope * pulse


func _apply_signal_feedback_visuals(_strength: float) -> void:
	pass


func _get_signal_feedback_scale_target() -> Node2D:
	return self


func _reset_signal_feedback() -> void:
	_signal_feedback_time_left = 0.0
	if _signal_feedback_scale_target != null:
		_signal_feedback_scale_target.scale = _signal_feedback_base_scale
	_apply_signal_feedback_visuals(0.0)
	set_process(false)


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
