extends Node2D
class_name Producer

enum Direction {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

const DEFAULT_CARGO_TYPE: String = "CARGO_1"

@export var facing: Direction = Direction.RIGHT:
	set(value):
		facing = value

@export_range(1, 16, 1) var beat_interval: int = 2:
	set(value):
		beat_interval = maxi(value, 1)

@export var cargo_type: String = DEFAULT_CARGO_TYPE:
	set(value):
		cargo_type = _normalize_cargo_type(value)

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false


func _ready() -> void:
	_world = GM.current_world
	_register_to_producer_layer()


func _exit_tree() -> void:
	_unregister_from_producer_layer()


func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % beat_interval == 0


func get_registered_cell() -> Vector2i:
	return _registered_cell


func get_target_cell() -> Vector2i:
	return _registered_cell + _direction_to_offset(facing)


func _register_to_producer_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.producer_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_producer_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.producer_layer.get_cell(_registered_cell) == self:
		_world.producer_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func _direction_to_offset(direction: Direction) -> Vector2i:
	match direction:
		Direction.UP:
			return Vector2i.UP
		Direction.RIGHT:
			return Vector2i.RIGHT
		Direction.DOWN:
			return Vector2i.DOWN
		_:
			return Vector2i.LEFT


static func _normalize_cargo_type(value: Variant) -> String:
	var normalized_value: String = String(value).strip_edges().to_upper()
	return normalized_value if not normalized_value.is_empty() else DEFAULT_CARGO_TYPE
