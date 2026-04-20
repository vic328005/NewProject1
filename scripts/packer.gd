extends Node2D
class_name Packer

# 打包机只在信号触发时吃入 Cargo，
# 然后在开始阶段把 Cargo 转成待出料的 Product，
# 下一拍进入可出料状态。

const IDLE_ANIMATION: StringName = &"idle"
const WORK_ANIMATION: StringName = &"work"

# 机器朝向决定出料目标格。
var facing: Direction.Value = Direction.Value.RIGHT

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# 机器内部当前暂存的原料。进入打包流程前，Cargo 会先停留在这里。
var _held_cargo: Cargo
# 打包完成后，这里记录即将生成的 Product 类型。
var _pending_output_product_type: String = ""
# 允许出料的拍点。-1 表示当前没有待出料内容。
var _output_ready_beat: int = -1


# 初始化打包机引用，并在场景进入时同步动画和图层登记。
func _ready() -> void:
	# 先同步一次动画状态，避免场景初次进入时精灵停在错误动画上。
	_update_animation()

	_world = GM.world
	_register_to_packer_layer()


# 在节点离开场景树时注销自己在打包机图层中的登记。
func _exit_tree() -> void:
	_unregister_from_packer_layer()


# 返回打包机当前登记到世界图层的格子坐标。
func get_registered_cell() -> Vector2i:
	return _registered_cell


# 根据朝向计算打包机的目标出料格。
func get_target_cell() -> Vector2i:
	# 打包机固定向朝向前方出料。
	return _registered_cell + Direction.to_vector2i(facing)


# 判断当前是否存在尚未落地到地图的待出料 Product。
func has_pending_output() -> bool:
	return _pending_output_product_type != ""


# 判断指定拍点是否已经到达允许出料的时机。
func can_output_on_beat(beat_index: int) -> bool:
	return has_pending_output() and beat_index >= _output_ready_beat


# 返回当前待出料的 Product 类型，要求外部先确认确实有待出料。
func get_pending_output_product_type() -> String:
	assert(has_pending_output(), "Packer has no pending output.")
	return _pending_output_product_type


# 在出料成功提交后清空待出料状态并刷新动画。
func commit_output_success() -> void:
	# Product 真正生成到地图后，清空待出料状态。
	_pending_output_product_type = ""
	_output_ready_beat = -1
	_update_animation()


# 判断当前拍点是否允许机器吃入新的 Cargo。
func can_accept_input(is_triggered: bool) -> bool:
	_clear_invalid_held_cargo()
	# 只有被信号触发、机内为空、且没有待出料时才允许吃入 Cargo。
	return is_triggered and _held_cargo == null and not has_pending_output()


# 将输入的 Cargo 收入机器内部，进入待打包状态。
func accept_input(cargo: Cargo) -> void:
	assert(cargo != null and is_instance_valid(cargo), "Packer requires a valid Cargo to accept input.")
	_clear_invalid_held_cargo()
	assert(_held_cargo == null, "Packer cannot accept input while occupied.")
	cargo.store_in_machine(global_position)
	_held_cargo = cargo
	_update_animation()


# 判断本拍是否满足启动一次打包流程的条件。
func can_start_cycle(beat_index: int, is_triggered: bool) -> bool:
	_clear_invalid_held_cargo()
	# 开始打包前必须已经持有原料，且当前没有上一轮的待出料残留。
	return is_triggered and _held_cargo != null and is_instance_valid(_held_cargo) and not has_pending_output()


# 启动打包流程，把机内 Cargo 转成下一拍可出的 Product 记录。
func start_cycle(beat_index: int) -> void:
	_clear_invalid_held_cargo()
	assert(_held_cargo != null and is_instance_valid(_held_cargo), "Packer requires held Cargo to start packing.")
	# 打包阶段不立即生成 Product，而是先记录类型并延后一拍出料。
	_pending_output_product_type = _held_cargo.cargo_type
	_output_ready_beat = beat_index + 1
	_held_cargo.remove_from_world()
	_held_cargo = null
	_update_animation()


# 判断运输物经过本格时是否可以直接穿过打包机。
func allows_pass_through(item: TransportItem, is_triggered: bool) -> bool:
	_clear_invalid_held_cargo()
	# 机内占用或已有待出料时，任何运输物都不能穿过该格。
	if _held_cargo != null or has_pending_output():
		return false

	# 被触发时，Cargo 应该被机器吃入，不能继续直通。
	if item is Cargo and is_triggered:
		return false

	return true


# 清理已经失效的内部 Cargo 引用，避免机器状态悬空。
func _clear_invalid_held_cargo() -> void:
	# 某些情况下内部 Cargo 可能已被外部销毁，这里顺手把悬空引用清掉。
	if _held_cargo != null and not is_instance_valid(_held_cargo):
		_held_cargo = null
		_update_animation()


# 把自己登记到世界的打包机图层，并校正到格子中心位置。
func _register_to_packer_layer() -> void:
	if _world == null:
		return

	# 进入世界后把自己登记到打包机图层，并对齐到格子中心。
	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.packer_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


# 从世界的打包机图层移除自己的登记。
func _unregister_from_packer_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	# 只移除仍然指向自己的格子，避免误删后来替换进来的对象。
	if _world.packer_layer.get_cell(_registered_cell) == self:
		_world.packer_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


# 根据当前是否持有原料或待出料状态切换播放动画。
func _update_animation() -> void:
	# 只要机内有原料，或已经打包完成但还没出料，都视为工作中。
	var target_animation: StringName = IDLE_ANIMATION
	if _held_cargo != null or has_pending_output():
		target_animation = WORK_ANIMATION

	# 动画切换时直接播放目标动画；没切换但意外停播时则补一次播放。
	if _animated_sprite.animation != target_animation:
		_animated_sprite.play(target_animation)
		return

	if not _animated_sprite.is_playing():
		_animated_sprite.play()
