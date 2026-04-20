extends Machine
class_name PressMachine

const PREVIEW_CELL_SIZE: float = 64.0
const PREVIEW_CENTER: Vector2 = Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.5)
const DEFAULT_CARGO_TYPE: String = CargoType.DEFAULT
const DEFAULT_BEAT_INTERVAL: int = 2
const ANIMATION_A: StringName = &"A"
const ANIMATION_B: StringName = &"B"
const ANIMATION_C: StringName = &"C"

enum AnimationState {
	IDLE,
	WORK,
}

enum MachineState {
	IDLE,
	WORK,
}

@export var facing: Direction.Value = Direction.Value.RIGHT:
	set(value):
		facing = value
		_sync_visual_state()
		_update_animation()
		queue_redraw()

@export var cargo_type: String = DEFAULT_CARGO_TYPE:
	set(value):
		cargo_type = CargoType.normalize(value)
		_sync_visual_state()
		_update_animation()
		queue_redraw()

@export_range(1, 2, 1) var beat_interval: int = DEFAULT_BEAT_INTERVAL:
	set(value):
		beat_interval = clampi(value, 1, 2)
		_sync_visual_state()
		_update_animation()
		queue_redraw()

var _pressed_item: Item
var _press_start_beat: int = -1
var _output_ready_beat: int = -1
var _animated_sprite: AnimatedSprite2D
var _machine_state: MachineState = MachineState.IDLE


func _ready() -> void:
	_enter_idle_state()
	queue_redraw()
	super._ready()


func _exit_tree() -> void:
	super._exit_tree()


func get_target_cell() -> Vector2i:
	return _registered_cell + Direction.to_vector2i(facing)


func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % beat_interval == 0


func plan_output(beat_index: int, _receives_signal: bool) -> Dictionary:
	if not _has_valid_pressed_item():
		return {
			"action": "none",
		}

	if _output_ready_beat < 0 or beat_index < _output_ready_beat:
		return {
			"action": "none",
		}

	return {
		"action": "release",
		"target_cell": get_target_cell(),
		"item": _pressed_item,
		"flow_direction": facing,
	}


func plan_transport(item: Item, beat_index: int, receives_signal: bool) -> Dictionary:
	if _is_working():
		return {
			"action": "block",
		}

	if item.is_cargo() and _is_triggered_on_beat(beat_index, receives_signal):
		return {
			"action": "block",
		}

	# 未触发时按直通处理，沿用传送带的隔拍节奏。
	if not _should_pass_through_on_beat(beat_index):
		return {
			"action": "block",
		}

	return {
		"action": "move",
		"target_cell": get_target_cell(),
		"flow_direction": facing,
	}


func plan_input(item: Item, beat_index: int, receives_signal: bool) -> Dictionary:
	if item == null or not is_instance_valid(item):
		return {
			"action": "reject",
		}

	if not item.is_cargo():
		return {
			"action": "reject",
		}

	if not _is_triggered_on_beat(beat_index, receives_signal):
		return {
			"action": "reject",
		}

	# 压塑机被触发但正在压塑另一块原料（或待出料），原料被损毁。
	if _is_working():
		return {
			"action": "destroy",
		}

	return {
		"action": "accept",
	}


func clear_pressed_item() -> void:
	_pressed_item = null
	_press_start_beat = -1
	_output_ready_beat = -1
	_enter_idle_state()


func _is_working() -> bool:
	return _machine_state == MachineState.WORK


func _has_valid_pressed_item() -> bool:
	return _pressed_item != null and is_instance_valid(_pressed_item)


func _enter_work_state(item: Item) -> void:
	_pressed_item = item
	_press_start_beat = -1
	_output_ready_beat = -1
	_machine_state = MachineState.WORK
	_sync_visual_state()
	_update_animation()


func _enter_idle_state() -> void:
	_machine_state = MachineState.IDLE
	_sync_visual_state()
	_update_animation()


func _sync_visual_state() -> void:
	if not is_inside_tree():
		return

	var animated_sprite: AnimatedSprite2D = _get_animated_sprite()
	var target_animation: StringName = _get_animation_name_for_cargo_type()

	if animated_sprite.animation != target_animation:
		animated_sprite.animation = target_animation


func _get_animation_name(state: AnimationState) -> StringName:
	match state:
		AnimationState.IDLE:
			return _get_animation_name_for_cargo_type()
		AnimationState.WORK:
			return _get_animation_name_for_cargo_type()

	return _get_animation_name_for_cargo_type()


func _update_animation_speed(target_animation: StringName) -> void:
	var animated_sprite: AnimatedSprite2D = _get_animated_sprite()
	if not _is_working():
		animated_sprite.speed_scale = 1.0
		return

	var beat_interval_seconds: float = _get_current_beat_interval_seconds()
	if beat_interval_seconds <= 0.0:
		animated_sprite.speed_scale = 1.0
		return

	var base_duration_seconds: float = _get_animation_base_duration_seconds(target_animation)
	if base_duration_seconds <= 0.0:
		animated_sprite.speed_scale = 1.0
		return

	# work 动画完整循环一遍刚好覆盖一个 beat。
	animated_sprite.speed_scale = base_duration_seconds / beat_interval_seconds


func _get_current_beat_interval_seconds() -> float:
	if GM == null or not is_instance_valid(GM.beats):
		return 0.0

	return GM.beats.get_beat_interval_seconds()


func _get_animation_base_duration_seconds(animation_name: StringName) -> float:
	var animated_sprite: AnimatedSprite2D = _get_animated_sprite()
	var sprite_frames: SpriteFrames = animated_sprite.sprite_frames
	if sprite_frames == null or not sprite_frames.has_animation(animation_name):
		return 0.0

	var animation_speed: float = sprite_frames.get_animation_speed(animation_name)
	if animation_speed <= 0.0:
		return 0.0

	var frame_count: int = sprite_frames.get_frame_count(animation_name)
	if frame_count <= 0:
		return 0.0

	var total_frame_duration: float = 0.0
	for frame_index in frame_count:
		total_frame_duration += sprite_frames.get_frame_duration(animation_name, frame_index)

	return total_frame_duration / animation_speed


func _update_animation() -> void:
	if not is_inside_tree():
		return

	var target_state: AnimationState = AnimationState.IDLE
	if _is_working():
		target_state = AnimationState.WORK

	var animated_sprite: AnimatedSprite2D = _get_animated_sprite()
	var target_animation: StringName = _get_animation_name(target_state)
	_update_animation_speed(target_animation)

	if target_state == AnimationState.IDLE:
		if animated_sprite.animation != target_animation:
			animated_sprite.animation = target_animation

		animated_sprite.stop()
		animated_sprite.frame = 0
		animated_sprite.frame_progress = 0.0
		return

	if animated_sprite.animation != target_animation:
		animated_sprite.play(target_animation)
		return

	if not animated_sprite.is_playing():
		animated_sprite.play()


func _get_animated_sprite() -> AnimatedSprite2D:
	if _animated_sprite == null:
		_animated_sprite = get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D

	assert(_animated_sprite != null, "PressMachine must have an AnimatedSprite2D child.")
	return _animated_sprite


func _get_animation_name_for_cargo_type() -> StringName:
	match cargo_type:
		CargoType.B:
			return ANIMATION_B
		CargoType.C:
			return ANIMATION_C
		_:
			return ANIMATION_A


func _draw() -> void:
	var shape_color: Color = _get_shape_color()
	var arrow_tip: Vector2 = PREVIEW_CENTER + _direction_to_vector(facing) * 16.0
	var arrow_tail: Vector2 = PREVIEW_CENTER - _direction_to_vector(facing) * 8.0
	draw_line(arrow_tail, arrow_tip, Color(0.18, 0.14, 0.08, 1.0), 4.0)
	_draw_arrow_head(arrow_tip, _direction_to_vector(facing))

	match cargo_type:
		CargoType.B:
			draw_circle(PREVIEW_CENTER, 12.0, shape_color)
			draw_arc(PREVIEW_CENTER, 12.0, 0.0, TAU, 24, Color.BLACK, 2.0)
		CargoType.C:
			draw_rect(Rect2(PREVIEW_CENTER - Vector2.ONE * 11.0, Vector2.ONE * 22.0), shape_color, true)
			draw_rect(Rect2(PREVIEW_CENTER - Vector2.ONE * 11.0, Vector2.ONE * 22.0), Color.BLACK, false, 2.0)
		_:
			var triangle_points: PackedVector2Array = PackedVector2Array([
				PREVIEW_CENTER + Vector2(0.0, -14.0),
				PREVIEW_CENTER + Vector2(13.0, 11.0),
				PREVIEW_CENTER + Vector2(-13.0, 11.0),
			])
			var closed_triangle_points: PackedVector2Array = PackedVector2Array([
				triangle_points[0],
				triangle_points[1],
				triangle_points[2],
				triangle_points[0],
			])
			draw_colored_polygon(triangle_points, shape_color)
			draw_polyline(closed_triangle_points, Color.BLACK, 2.0)


func _draw_arrow_head(tip: Vector2, direction: Vector2) -> void:
	var normalized_direction: Vector2 = direction.normalized()
	var normal: Vector2 = Vector2(-normalized_direction.y, normalized_direction.x)
	var arrow_size: float = 8.0
	draw_colored_polygon(
		PackedVector2Array([
			tip,
			tip - normalized_direction * arrow_size + normal * (arrow_size * 0.6),
			tip - normalized_direction * arrow_size - normal * (arrow_size * 0.6),
		]),
		Color(0.18, 0.14, 0.08, 1.0)
	)


func _direction_to_vector(direction: Direction.Value) -> Vector2:
	match direction:
		Direction.Value.UP:
			return Vector2.UP
		Direction.Value.RIGHT:
			return Vector2.RIGHT
		Direction.Value.DOWN:
			return Vector2.DOWN
		_:
			return Vector2.LEFT


func _get_shape_color() -> Color:
	match cargo_type:
		CargoType.B:
			return Color(0.64, 0.92, 0.73, 1.0)
		CargoType.C:
			return Color(0.62, 0.56, 0.98, 1.0)
		_:
			return Color(0.96, 0.89, 0.72, 1.0)


func _is_triggered_on_beat(beat_index: int, receives_signal: bool) -> bool:
	if not receives_signal:
		return false

	return should_trigger_on_beat(beat_index)


# 未触发时直通沿用 Belt 的隔拍节奏（beat_interval = 2）。
func _should_pass_through_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % 2 == 0
