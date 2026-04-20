extends Machine
class_name Belt

enum TurnMode {
	STRAIGHT,
	LEFT,
	RIGHT,
}

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

var _animated_sprite: AnimatedSprite2D


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
	if _animated_sprite == null:
		_animated_sprite = get_node_or_null(^"Sprite2D/AnimatedSprite2D") as AnimatedSprite2D

	if _animated_sprite == null:
		return

	var target_animation: StringName = _get_animation_name()
	if _animated_sprite.animation != target_animation:
		_animated_sprite.play(target_animation)
		return

	if turn_mode == TurnMode.STRAIGHT:
		if not _animated_sprite.is_playing():
			_animated_sprite.play()
		return

	if not _animated_sprite.is_playing():
		_animated_sprite.play()


func _get_animation_name() -> StringName:
	if turn_mode == TurnMode.STRAIGHT:
		return _get_straight_animation_name()

	return _get_turn_animation_name()


func _get_straight_animation_name() -> StringName:
	match facing:
		Direction.Value.UP:
			return &"up"
		Direction.Value.RIGHT:
			return &"right"
		Direction.Value.DOWN:
			return &"down"
		_:
			return &"left"


func _get_turn_animation_name() -> StringName:
	var prefix: String = "turn1"
	if turn_mode == TurnMode.RIGHT:
		prefix = "turn2"

	var suffix: String = "up"
	if facing == Direction.Value.DOWN or facing == Direction.Value.LEFT:
		suffix = "down"

	return StringName("%s-%s" % [prefix, suffix])
