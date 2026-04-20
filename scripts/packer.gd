extends Machine
class_name Packer

# 打包机只在信号触发时吃入 Cargo 形态的 Item，
# 然后在结算里的机器状态更新中把它转成待出料的 Product，
# 下一拍进入可出料状态。

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

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# 机器内部当前暂存的原料。进入打包流程前，Item 会先停留在这里。
var _held_item: Item
# 打包机当前业务状态。进入工作态后要完整跑完一拍并产出后才回到空闲态。
var _machine_state: MachineState = MachineState.IDLE
# 打包完成后，这里记录即将生成的 Product 类型。
var _pending_output_item_type: String = ""
# 允许出料的拍点。-1 表示当前没有待出料内容。
var _output_ready_beat: int = -1


# 初始化打包机引用，并在场景进入时同步动画和图层登记。
func _ready() -> void:
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


# 判断当前是否存在尚未落地到地图的待出料 Product。
func plan_output(beat_index: int, _receives_signal: bool) -> Dictionary:
	if _pending_output_item_type == "" or beat_index < _output_ready_beat:
		return {
			"action": "none",
		}

	return {
		"action": "spawn",
		"target_cell": get_target_cell(),
		"item_type": _pending_output_item_type,
		"item_kind": Item.Kind.PRODUCT,
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


func _get_animation_name(state: AnimationState) -> StringName:
	match state:
		AnimationState.IDLE:
			return &"idle"
		AnimationState.WORK:
			return &"work"

	return &"idle"


func _update_animation_speed(target_animation: StringName) -> void:
	if _animated_sprite == null:
		return

	if target_animation != &"work":
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
	if _is_working():
		target_state = AnimationState.WORK

	var target_animation: StringName = _get_animation_name(target_state)
	_update_animation_speed(target_animation)

	# 动画切换时直接播放目标动画；没切换但意外停播时则补一次播放。
	if _animated_sprite.animation != target_animation:
		_animated_sprite.play(target_animation)
		return

	if not _animated_sprite.is_playing():
		_animated_sprite.play()


func _is_triggered_on_beat(_beat_index: int, receives_signal: bool) -> bool:
	return receives_signal


# idle 直通时沿用 Belt 的隔拍节奏（beat_interval = 2）。
func _should_pass_through_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % 2 == 0
