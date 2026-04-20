extends Machine
class_name Packer

# 打包机只在信号触发时吃入 Cargo 形态的 Item，
# 然后在开始阶段把它转成待出料的 Product，
# 下一拍进入可出料状态。

const IDLE_ANIMATION: StringName = &"idle"
const WORK_ANIMATION: StringName = &"work"

# 机器朝向决定出料目标格。
var facing: Direction.Value = Direction.Value.RIGHT

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# 机器内部当前暂存的原料。进入打包流程前，Item 会先停留在这里。
var _held_item: Item
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
func output(beat_index: int) -> Dictionary:
	if _pending_output_item_type == "" or beat_index < _output_ready_beat:
		return {
			"action": "none",
		}

	return {
		"action": "spawn",
		"target_cell": get_target_cell(),
		"item_type": _pending_output_item_type,
		"item_kind": Item.Kind.PRODUCT,
		"on_success": Callable(self, "_commit_output_success"),
	}


func input(item: Item, beat_index: int) -> String:
	_clear_invalid_held_item()
	if item == null or not is_instance_valid(item):
		return "reject"

	if not item.is_cargo():
		return "reject"

	if not _is_triggered_on_beat(beat_index):
		return "reject"

	if _held_item != null or _pending_output_item_type != "":
		return "reject"

	item.store_in_machine(global_position)
	_held_item = item
	_update_animation()
	return "accept"


func transport(item: Item, beat_index: int) -> Dictionary:
	_clear_invalid_held_item()
	if _held_item != null or _pending_output_item_type != "":
		return {
			"action": "block",
		}

	if item.is_cargo() and _is_triggered_on_beat(beat_index):
		return {
			"action": "block",
		}

	return {
		"action": "move",
		"target_cell": get_target_cell(),
	}


func start(beat_index: int) -> void:
	_clear_invalid_held_item()
	if not _is_triggered_on_beat(beat_index):
		return

	if _held_item == null or not is_instance_valid(_held_item):
		return

	if _pending_output_item_type != "":
		return

	_pending_output_item_type = _held_item.item_type
	_output_ready_beat = beat_index + 1
	_held_item.remove_from_world()
	_held_item = null
	_update_animation()


# 清理已经失效的内部 Item 引用，避免机器状态悬空。
func _clear_invalid_held_item() -> void:
	# 某些情况下内部 Item 可能已被外部销毁，这里顺手把悬空引用清掉。
	if _held_item != null and not is_instance_valid(_held_item):
		_held_item = null
		_update_animation()


# 根据当前是否持有原料或待出料状态切换播放动画。
func _update_animation() -> void:
	# 只要机内有原料，或已经打包完成但还没出料，都视为工作中。
	var target_animation: StringName = IDLE_ANIMATION
	if _held_item != null or _pending_output_item_type != "":
		target_animation = WORK_ANIMATION

	# 动画切换时直接播放目标动画；没切换但意外停播时则补一次播放。
	if _animated_sprite.animation != target_animation:
		_animated_sprite.play(target_animation)
		return

	if not _animated_sprite.is_playing():
		_animated_sprite.play()


func _is_triggered_on_beat(_beat_index: int) -> bool:
	return _world != null and _world.signal_layer.has_cell(_registered_cell)


func _commit_output_success() -> void:
	_pending_output_item_type = ""
	_output_ready_beat = -1
	_update_animation()
