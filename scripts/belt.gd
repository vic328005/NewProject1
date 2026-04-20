extends Machine
class_name Belt

enum TurnMode {
	STRAIGHT,
	LEFT,
	RIGHT,
}

const STRAIGHT_INTERVAL_1_TEXTURE: Texture2D = preload("res://assets/images/belt_straight_interval_1.png")
const STRAIGHT_INTERVAL_2_TEXTURE: Texture2D = preload("res://assets/images/belt_straight_interval_2.png")
const TURN_INTERVAL_1_TEXTURE: Texture2D = preload("res://assets/images/belt_turn_interval_1.png")
const TURN_INTERVAL_2_TEXTURE: Texture2D = preload("res://assets/images/belt_turn_interval_2.png")

var facing: Direction.Value = Direction.Value.RIGHT:
	set(value):
		facing = value
		_update_sprite_visual()

var turn_mode: TurnMode = TurnMode.STRAIGHT:
	set(value):
		turn_mode = value
		_update_sprite_visual()

var beat_interval: int = 2:
	set(value):
		beat_interval = clampi(value, 1, 2)
		_update_sprite_visual()

var _sprite: Sprite2D


func _ready() -> void:
	_update_sprite_visual()
	super._ready()


func _exit_tree() -> void:
	super._exit_tree()


func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % beat_interval == 0


func get_target_cell() -> Vector2i:
	return _registered_cell + Direction.to_vector2i(_get_output_direction())


func output(_beat_index: int) -> Dictionary:
	return {
		"action": "none",
	}


func input(_item: Item, _beat_index: int) -> String:
	return "reject"


func transport(_item: Item, beat_index: int) -> Dictionary:
	if not should_trigger_on_beat(beat_index):
		return {
			"action": "block",
		}

	return {
		"action": "move",
		"target_cell": get_target_cell(),
	}


func start(_beat_index: int) -> void:
	pass


func _get_output_direction() -> Direction.Value:
	match turn_mode:
		TurnMode.LEFT:
			return Direction.rotate_left(facing)
		TurnMode.RIGHT:
			return Direction.rotate_right(facing)
		_:
			return facing


func _update_sprite_visual() -> void:
	if _sprite == null:
		_sprite = get_node_or_null(^"Sprite2D") as Sprite2D

	if _sprite == null:
		return

	_sprite.texture = _get_belt_texture()
	_sprite.rotation_degrees = _get_sprite_rotation_degrees()
	_sprite.flip_h = turn_mode == TurnMode.LEFT
	_sprite.flip_v = false


func _get_belt_texture() -> Texture2D:
	if turn_mode == TurnMode.STRAIGHT:
		if beat_interval == 1:
			return STRAIGHT_INTERVAL_1_TEXTURE

		return STRAIGHT_INTERVAL_2_TEXTURE

	if beat_interval == 1:
		return TURN_INTERVAL_1_TEXTURE

	return TURN_INTERVAL_2_TEXTURE


func _get_rotation_degrees_for_direction(direction: Direction.Value) -> float:
	match direction:
		Direction.Value.UP:
			return -90.0
		Direction.Value.RIGHT:
			return 0.0
		Direction.Value.DOWN:
			return 90.0
		_:
			return 180.0


func _get_sprite_rotation_degrees() -> float:
	if turn_mode == TurnMode.STRAIGHT:
		return wrapf(_get_rotation_degrees_for_direction(facing), 0.0, 360.0)

	return wrapf(float(int(facing)) * 90.0, 0.0, 360.0)
