extends Node2D
class_name Item

# 场上统一的运输物实体。
# 它同时承载原来的 cargo / product 两种概念，
# 负责：
# 1. 记录自身类型与形态。
# 2. 在 World.item_layer 中登记占格。
# 3. 处理运输移动、入机、出机时的位置切换。
# 4. 根据当前形态与类型刷新贴图表现。

# 运输动画占一个拍子的比例。
# 适当压缩拍内移动时长，让传送带运输看起来更利落。
const MOVE_DURATION_RATIO: float = 0.4

# Cargo 形态下三种类型对应的贴图。
const CARGO_TEXTURE_1: Texture2D = preload("res://assets/images/cargo_1.png")
const CARGO_TEXTURE_2: Texture2D = preload("res://assets/images/cargo_2.png")
const CARGO_TEXTURE_3: Texture2D = preload("res://assets/images/cargo_3.png")

# Product 形态下三种类型对应的贴图。
const PRODUCT_TEXTURE_1: Texture2D = preload("res://assets/images/product_1.png")
const PRODUCT_TEXTURE_2: Texture2D = preload("res://assets/images/product_2.png")
const PRODUCT_TEXTURE_3: Texture2D = preload("res://assets/images/product_3.png")

# Item 当前处于哪种业务形态。
# CARGO 表示原料/半成品，PRODUCT 表示已打包成品。
enum Kind {
	CARGO,
	PRODUCT,
}

# 内部存储的物体类型。
# 通过 item_type 属性访问，保证写入时统一归一化。
var _item_type: String = CargoType.DEFAULT
# 内部存储的物体形态。
# 通过 item_kind 属性访问，保证变更后刷新显示。
var _item_kind: Kind = Kind.CARGO

# 对外暴露的物体类型属性。
# 写入时会统一做 normalize，并同步刷新贴图。
var item_type: String:
	get:
		return _item_type
	set(value):
		_item_type = CargoType.normalize(value)
		_update_visual_state()

# 对外暴露的物体形态属性。
# 切换 cargo / product 时只改形态，不改变底层类型值。
var item_kind: Kind:
	get:
		return _item_kind
	set(value):
		_item_kind = value
		_update_visual_state()

# 当前所属世界。由 place_at_cell() 或 _ready() 注入。
var _world: World
# 当前登记到 item_layer 的格子坐标。
var _registered_cell: Vector2i
# 是否已经登记到世界的 item_layer。
var _is_registered_to_layer: bool = false
# 当前正在播放的移动动画；没有动画时为 null。
var _move_tween: Tween
# 最近一次参与结算的拍点编号。
# 目前主要由 WorldSimulation 写入，给后续扩展保留状态。
var last_resolved_beat: int = -1
# 当前物体流入所在格子的方向。
# 只有运输链路相关逻辑会读取它，未初始化时视为无方向状态。
var _flow_direction: Direction.Value = Direction.Value.RIGHT
var _has_flow_direction: bool = false
# 精灵节点引用，用于刷新外观。
@onready var _sprite: Sprite2D = $Sprite2D


# 节点进入场景树后的初始化入口。
# 这里负责：
# 1. 先按当前属性刷新一次贴图。
# 2. 若外部还没注入 world，则回退到 GM.world。
# 3. 若还没登记到 item_layer，则按当前位置自动登记。
func _ready() -> void:
	_update_visual_state()

	if _world == null:
		_world = GM.world

	if not _is_registered_to_layer:
		_register_to_item_layer()


# 节点离开场景树时清理瞬时状态。
# 这里要确保停止移动动画，并从世界占格层注销自己。
func _exit_tree() -> void:
	_stop_move_tween()
	_unregister_from_item_layer()


# 判断当前是否为 cargo 形态。
# 机器与回收逻辑用它来区分原料和成品的处理分支。
func is_cargo() -> bool:
	return _item_kind == Kind.CARGO


# 判断当前是否为 product 形态。
# 主要用于回收器与结算阶段的类型分流。
func is_product() -> bool:
	return _item_kind == Kind.PRODUCT


# 记录这个物体最近一次被哪个拍点结算过。
# 当前逻辑只写不读，但能保留“本拍已处理”这类语义痕迹。
func mark_resolved_on_beat(beat_index: int) -> void:
	last_resolved_beat = beat_index


func has_flow_direction() -> bool:
	return _has_flow_direction


func get_flow_direction() -> Direction.Value:
	return _flow_direction


func set_flow_direction(direction: Direction.Value) -> void:
	_flow_direction = direction
	_has_flow_direction = true


func clear_flow_direction() -> void:
	_has_flow_direction = false


# 直接把物体放到指定世界和格子。
# 常用于初始生成、关卡加载或机器出料后的落位。
# 这个方法会立即更新占格，并把节点对齐到格子中心。
func place_at_cell(world: World, cell: Vector2i) -> void:
	_world = world
	_registered_cell = cell
	_stop_move_tween()
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_world.item_layer.set_cell(_registered_cell, self)
	_is_registered_to_layer = true


# 把物体收入机器内部。
# 进入机器后它会暂时脱离 item_layer，只保留一个锚点世界坐标。
# 这样后续机器内部处理就不会再参与地图占格判定。
func store_in_machine(anchor_global_position: Vector2) -> void:
	if _world == null:
		return

	_stop_move_tween()
	if _is_registered_to_layer and _world.item_layer.get_cell(_registered_cell) == self:
		_world.item_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false
	global_position = anchor_global_position


# 把物体从机器内部释放到指定格子。
# 只有目标格为空时才会成功；成功后会重新登记占格并播放移动动画。
func deploy_from_machine(target_cell: Vector2i, flow_direction: Direction.Value) -> bool:
	if _world == null:
		return false

	if _world.item_layer.has_cell(target_cell):
		return false

	_stop_move_tween()
	_registered_cell = target_cell
	_world.item_layer.set_cell(target_cell, self)
	_is_registered_to_layer = true
	set_flow_direction(flow_direction)
	var target_global_position: Vector2 = _world.to_global(_world.cell_to_world(target_cell))
	_start_move_to_global_position(target_global_position)
	return true


# 并行移动阶段的前半段。
# WorldSimulation 会先统一调用它，把本拍所有成功移动的物体暂时从占格层移除，
# 这样可以避免“先提交的物体影响后提交物体”的顺序问题。
func begin_parallel_move() -> void:
	if _world == null or not _is_registered_to_layer:
		return

	if _world.item_layer.get_cell(_registered_cell) == self:
		_world.item_layer.erase_cell(_registered_cell)


# 并行移动阶段的后半段。
# 在所有成功移动都确认后，再统一把物体登记到目标格并播放动画。
func complete_parallel_move(target_cell: Vector2i, flow_direction: Direction.Value) -> void:
	if _world == null:
		return

	_registered_cell = target_cell
	_world.item_layer.set_cell(target_cell, self)
	_is_registered_to_layer = true
	set_flow_direction(flow_direction)
	var target_global_position: Vector2 = _world.to_global(_world.cell_to_world(target_cell))
	_start_move_to_global_position(target_global_position)


# 把物体彻底从世界中移除。
# 用于被回收、被打包消耗，或其他需要销毁节点的场景。
func remove_from_world() -> void:
	_stop_move_tween()
	_unregister_from_item_layer()
	queue_free()


# 按当前世界坐标自动推导格子并登记到 item_layer。
# 主要用于场景直接放进世界、但尚未显式调用 place_at_cell() 的情况。
func _register_to_item_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.item_layer.set_cell(_registered_cell, self)
	_stop_move_tween()
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


# 从 item_layer 中注销当前占格。
# 只有登记表里当前格子仍然指向自己时才会擦除，避免误删后来者。
func _unregister_from_item_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.item_layer.get_cell(_registered_cell) == self:
		_world.item_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


# 启动朝某个世界坐标的线性移动动画。
# 如果目标点就是当前位置，或当前拍长为 0，则直接瞬移过去。
func _start_move_to_global_position(target_global_position: Vector2) -> void:
	_stop_move_tween()

	if global_position.is_equal_approx(target_global_position):
		global_position = target_global_position
		return

	var move_duration: float = _get_move_duration_seconds()
	if move_duration <= 0.0:
		global_position = target_global_position
		return

	_move_tween = create_tween()
	var move_tweener: PropertyTweener = _move_tween.tween_property(self, "global_position", target_global_position, move_duration)
	move_tweener.set_trans(Tween.TRANS_LINEAR)
	_move_tween.finished.connect(_on_move_tween_finished)


# 计算一次移动动画应持续多久。
# 时长来自节拍器拍长，并乘以 MOVE_DURATION_RATIO 做拍内视觉压缩。
func _get_move_duration_seconds() -> float:
	if not is_instance_valid(GM.beats):
		return 0.0

	return maxf(GM.beats.get_beat_interval_seconds() * MOVE_DURATION_RATIO, 0.0)


# 如果当前存在移动动画，则主动终止并清空引用。
# 在重新定位、入机、销毁前都要先调用，避免旧动画继续覆盖位置。
func _stop_move_tween() -> void:
	if not is_instance_valid(_move_tween):
		return

	_move_tween.kill()
	_move_tween = null


# Tween 正常播放结束后的回调。
# 这里只负责清理引用，不做额外逻辑。
func _on_move_tween_finished() -> void:
	_move_tween = null


# 根据当前 item_kind 与 item_type 刷新精灵贴图。
# 如果节点还没 ready、精灵还不存在，则直接跳过。
func _update_visual_state() -> void:
	if _sprite == null:
		return

	_sprite.texture = _get_texture_for_state(_item_kind, _item_type)


# 为给定的形态和类型选择最终贴图。
# 先选 cargo / product 对应的贴图组，再按 A/B/C 返回具体纹理。
func _get_texture_for_state(kind: Kind, type_name: String) -> Texture2D:
	var texture_1: Texture2D = CARGO_TEXTURE_1
	var texture_2: Texture2D = CARGO_TEXTURE_2
	var texture_3: Texture2D = CARGO_TEXTURE_3
	if kind == Kind.PRODUCT:
		texture_1 = PRODUCT_TEXTURE_1
		texture_2 = PRODUCT_TEXTURE_2
		texture_3 = PRODUCT_TEXTURE_3

	match type_name:
		CargoType.B:
			return texture_2
		CargoType.C:
			return texture_3
		_:
			return texture_1
