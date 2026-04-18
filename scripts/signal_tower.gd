extends Node2D
class_name SignalTower

const DEFAULT_MAX_STEPS: int = 10
const SIGNAL_SCENE: PackedScene = preload("res://prefabs/signal_wave.tscn")

@export_range(1, 64, 1) var max_steps: int = DEFAULT_MAX_STEPS:
	set(value):
		max_steps = maxi(value, 1)

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false


func _ready() -> void:
	_world = GM.world
	_register_to_signal_tower_layer()


func _exit_tree() -> void:
	_unregister_from_signal_tower_layer()


func create_signal_wave(current_beat_index: int) -> SignalWave:
	var signal_wave: SignalWave = SIGNAL_SCENE.instantiate() as SignalWave
	assert(signal_wave != null, "Failed to instantiate Signal scene.")
	signal_wave.setup(_world, _registered_cell, max_steps, current_beat_index)
	return signal_wave


func get_registered_cell() -> Vector2i:
	return _registered_cell


func _register_to_signal_tower_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.signal_tower_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_signal_tower_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.signal_tower_layer.get_cell(_registered_cell) == self:
		_world.signal_tower_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false
