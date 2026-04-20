extends Machine
class_name Packer

const DEFAULT_TRANSPORT_BEAT_INTERVAL: int = 2
const IDLE_ANIMATION: StringName = &"idle"
const WORK_ANIMATION: StringName = &"work"
const SIGNAL_FEEDBACK_CENTER: Vector2 = Vector2(32.0, 16.0)
const SIGNAL_FEEDBACK_RING_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

# 打包机只在信号触发时吃入 Cargo 形态的 Item，
# 然后在同拍把它转成 Product 并立即尝试出料。

enum AnimationState {
	IDLE,
	WORK,
}

enum MachineState {
	IDLE,
	WORK,
}

# 机器朝向决定出料目标格。
var facing: Direction.Value = Direction.Value.RIGHT
var transport_beat_interval: int = DEFAULT_TRANSPORT_BEAT_INTERVAL:
	set(value):
		transport_beat_interval = clampi(value, 1, 2)

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# 机器内部当前暂存的原料。进入打包流程前，Item 会先停留在这里。
var _held_item: Item
# 打包机当前业务状态。逻辑上出料完成后立即回空闲。
var _machine_state: MachineState = MachineState.IDLE
# 逻辑已回空闲后，继续把 work 动画补播完整一轮。
var _is_playing_work_once: bool = false
var _signal_feedback_strength: float = 0.0


# 初始化打包机引用，并在场景进入时同步动画和图层登记。
func _ready() -> void:
	var sprite_frames: SpriteFrames = _animated_sprite.sprite_frames
	if sprite_frames != null and sprite_frames.has_animation(WORK_ANIMATION):
		sprite_frames.set_animation_loop(WORK_ANIMATION, false)

	if not _animated_sprite.animation_finished.is_connected(_on_animation_finished):
		_animated_sprite.animation_finished.connect(_on_animation_finished)

	# 先同步一次动画状态，避免场景初次进入时精灵停在错误动画上。
	_update_animation()
	super._ready()


# 在节点离开场景树时注销自己在打包机图层中的登记。
func _exit_tree() -> void:
	super._exit_tree()


# 根据朝向计算打包机的目标出料格。
func get_target_cell() -> Vector2i:
	# 打包机固定向朝向前方出料。
	return _registered_cell + Direction.to_vector2i(facing)


# 判断当前是否存在可立即推出的 Product。
func plan_output(_beat_index: int, _receives_signal: bool) -> Dictionary:
	if not _is_working():
		return {
			"action": "none",
		}

	if not _has_valid_held_item():
		return {
			"action": "none",
		}

	if not _held_item.is_product():
		return {
			"action": "none",
		}

	return {
		"action": "release",
		"target_cell": get_target_cell(),
		"item": _held_item,
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

	# idle 直通时遵循与 Belt 相同的隔拍节奏，避免 item 跳过等待拍。
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

	if _is_working():
		return {
			"action": "destroy",
		}

	if not item.is_cargo():
		return {
			"action": "reject",
		}

	if not _is_triggered_on_beat(beat_index, receives_signal):
		return {
			"action": "reject",
		}

	return {
		"action": "accept",
	}


func _is_working() -> bool:
	return _machine_state == MachineState.WORK


func _has_valid_held_item() -> bool:
	return _held_item != null and is_instance_valid(_held_item)


func _enter_work_state() -> void:
	_machine_state = MachineState.WORK
	_update_animation()


func _enter_idle_state() -> void:
	_machine_state = MachineState.IDLE
	_update_animation()


func _play_work_animation_once() -> void:
	_is_playing_work_once = true
	_update_animation()


func _get_animation_name(state: AnimationState) -> StringName:
	match state:
		AnimationState.IDLE:
			return IDLE_ANIMATION
		AnimationState.WORK:
			return WORK_ANIMATION

	return IDLE_ANIMATION


func _update_animation_speed(target_animation: StringName) -> void:
	if _animated_sprite == null:
		return

	if target_animation != WORK_ANIMATION:
		_animated_sprite.speed_scale = 1.0
		return

	var beat_interval_seconds: float = _get_current_beat_interval_seconds()
	if beat_interval_seconds <= 0.0:
		_animated_sprite.speed_scale = 1.0
		return

	var base_duration_seconds: float = _get_animation_base_duration_seconds(target_animation)
	if base_duration_seconds <= 0.0:
		_animated_sprite.speed_scale = 1.0
		return

	# work 动画完整循环一遍刚好覆盖一个 beat。
	_animated_sprite.speed_scale = base_duration_seconds / beat_interval_seconds


func _get_current_beat_interval_seconds() -> float:
	if GM == null or not is_instance_valid(GM.beats):
		return 0.0

	return GM.beats.get_beat_interval_seconds()


func _get_animation_base_duration_seconds(animation_name: StringName) -> float:
	if _animated_sprite == null:
		return 0.0

	var sprite_frames: SpriteFrames = _animated_sprite.sprite_frames
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


# 根据当前是否持有原料或待出料状态切换播放动画。
func _update_animation() -> void:
	var target_state: AnimationState = AnimationState.IDLE
	if _is_working() or _is_playing_work_once:
		target_state = AnimationState.WORK

	var target_animation: StringName = _get_animation_name(target_state)
	_update_animation_speed(target_animation)

	# 动画切换时直接播放目标动画；没切换但意外停播时则补一次播放。
	if _animated_sprite.animation != target_animation:
		_animated_sprite.play(target_animation)
		return

	if not _animated_sprite.is_playing():
		_animated_sprite.play()


func _on_animation_finished() -> void:
	if _animated_sprite == null:
		return

	if _animated_sprite.animation != WORK_ANIMATION:
		return

	if not _is_playing_work_once:
		return

	_is_playing_work_once = false
	if _is_working():
		return

	_update_animation()


func _draw() -> void:
	if _signal_feedback_strength <= 0.0:
		return

	var expansion_progress: float = 1.0 - _signal_feedback_strength
	var glow_radius: float = lerpf(18.0, 28.0, expansion_progress)
	var glow_color: Color = SIGNAL_FEEDBACK_RING_COLOR
	glow_color.a = 0.08 * _signal_feedback_strength
	draw_circle(SIGNAL_FEEDBACK_CENTER, glow_radius, glow_color)

	var ring_color: Color = SIGNAL_FEEDBACK_RING_COLOR
	ring_color.a = 0.55 * _signal_feedback_strength
	draw_arc(
		SIGNAL_FEEDBACK_CENTER,
		glow_radius + 2.0,
		0.0,
		TAU,
		32,
		ring_color,
		1.5 + 1.0 * _signal_feedback_strength
	)


func _apply_signal_feedback_visuals(strength: float) -> void:
	_signal_feedback_strength = strength
	if _animated_sprite != null:
		var flash_boost: float = strength * 0.28
		_animated_sprite.modulate = Color(
			1.0 + flash_boost,
			1.0 + flash_boost,
			1.0 + flash_boost,
			1.0
		)

	queue_redraw()


func _get_signal_feedback_scale_target() -> Node2D:
	return _animated_sprite


func _is_triggered_on_beat(_beat_index: int, receives_signal: bool) -> bool:
	return receives_signal


# idle 直通时使用关卡配置的运输节拍。
func _should_pass_through_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % transport_beat_interval == 0
