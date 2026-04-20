extends Machine
class_name Belt

# 传送带现在直接用“流入方向 -> 流出方向”描述自身形态。
# 直线带满足 input_direction == output_direction，
# 转弯带则要求两个方向垂直；关卡校验层会拦住 U 形回头配置。
var input_direction: Direction.Value = Direction.Value.RIGHT:
	set(value):
		input_direction = value
		_update_sprite_visual()

# output_direction 既决定物体下一拍要去的目标格，
# 也决定直线传送带该播放哪一组方向动画。
var output_direction: Direction.Value = Direction.Value.RIGHT:
	set(value):
		output_direction = value
		_update_sprite_visual()

# 节拍间隔只影响“这一拍能不能运输”，
# 不再参与任何 Belt 视觉分支。
var beat_interval: int = 2:
	set(value):
		beat_interval = clampi(value, 1, 2)
		_update_sprite_visual()

# Belt 场景里真正负责播放资源的是子节点 AnimatedSprite2D。
var _animated_sprite: AnimatedSprite2D


# 进入场景树时先同步一次视觉，
# 避免关卡加载后第一帧仍停在默认动画名上。
func _ready() -> void:
	_update_sprite_visual()
	super._ready()


func _exit_tree() -> void:
	super._exit_tree()


# Belt 仍然沿用“整拍触发”的运输规则。
func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % beat_interval == 0


# 目标格永远是当前格沿 output_direction 前进一格。
func get_target_cell() -> Vector2i:
	return _registered_cell + Direction.to_vector2i(output_direction)


func plan_output(_beat_index: int, _receives_signal: bool) -> Dictionary:
	return {
		"action": "none",
	}


# Belt 的严格入口规则在 transport 阶段判定：
# 1. 本拍未到触发时机则阻塞。
# 2. Item 无效或没有流动方向状态则阻塞。
# 3. 只有 item.flow_direction 与 belt.input_direction 一致时才允许运输。
# 成功运输后，会把 Item 下一格的流动方向写成 output_direction。
func plan_transport(item: Item, beat_index: int, _receives_signal: bool) -> Dictionary:
	if not should_trigger_on_beat(beat_index):
		return {
			"action": "block",
		}

	if item == null or not is_instance_valid(item):
		return {
			"action": "block",
		}

	if not item.has_flow_direction() or item.get_flow_direction() != input_direction:
		return {
			"action": "block",
		}

	return {
		"action": "move",
		"target_cell": get_target_cell(),
		"flow_direction": output_direction,
	}


func plan_input(_item: Item, _beat_index: int, _receives_signal: bool) -> Dictionary:
	return {
		"action": "reject",
	}


# 根据当前输入/输出方向切换动画。
# 这里不做 rotation / flip，动画名本身就是唯一真相。
func _update_sprite_visual() -> void:
	if _animated_sprite == null:
		_animated_sprite = get_node_or_null(^"Sprite2D/AnimatedSprite2D") as AnimatedSprite2D

	if _animated_sprite == null:
		return

	var target_animation: StringName = _get_animation_name()
	if _animated_sprite.animation != target_animation:
		_animated_sprite.play(target_animation)
		return

	if input_direction == output_direction:
		if not _animated_sprite.is_playing():
			_animated_sprite.play()
		return

	if not _animated_sprite.is_playing():
		_animated_sprite.play()


# 直线与转弯走两套不同命名规则，先在这里做分发。
func _get_animation_name() -> StringName:
	if input_direction == output_direction:
		return _get_straight_animation_name()

	return _get_turn_animation_name()


# 直线传送带直接按流出方向选择 up/right/down/left。
func _get_straight_animation_name() -> StringName:
	match output_direction:
		Direction.Value.UP:
			return &"up"
		Direction.Value.RIGHT:
			return &"right"
		Direction.Value.DOWN:
			return &"down"
		_:
			return &"left"


# 转弯动画的资源命名约定：
# 1. input -> output 若是右转，使用 turn2；否则使用 turn1。
# 2. up/down 后缀继续沿用当前美术资源分组：
#    input 为 UP / RIGHT 时落到 *-up，
#    input 为 DOWN / LEFT 时落到 *-down。
func _get_turn_animation_name() -> StringName:
	var prefix: String = "turn1"
	if output_direction == Direction.rotate_right(input_direction):
		prefix = "turn2"

	var suffix: String = "up"
	if input_direction == Direction.Value.DOWN or input_direction == Direction.Value.LEFT:
		suffix = "down"

	return StringName("%s-%s" % [prefix, suffix])
