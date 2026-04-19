extends Node2D
class_name Cargo

# 货物移动时长占一个节拍的比例。
# 例如节拍时长为 1 秒时，货物会在 0.9 秒内完成位移，预留少量空档避免视觉上过满。
const MOVE_DURATION_RATIO := 0.9

# 默认货物类型。用于导出属性未设置或传入空值时的回退。
const DEFAULT_CARGO_TYPE: String = "CARGO_1"

# 三种基础货物的贴图资源。
const CARGO_TEXTURE_1: Texture2D = preload("res://assets/images/cargo_1.png")
const CARGO_TEXTURE_2: Texture2D = preload("res://assets/images/cargo_2.png")
const CARGO_TEXTURE_3: Texture2D = preload("res://assets/images/cargo_3.png")

# 包装态外观使用的底色、边框色和三种绑带颜色。
# 绑带颜色会跟随基础货物类型变化，便于玩家快速分辨。
const PACKAGE_FILL_COLOR: Color = Color(0.95, 0.83, 0.57, 0.45)
const PACKAGE_BORDER_COLOR: Color = Color(0.40, 0.26, 0.12, 1.0)
const PACKAGE_RIBBON_COLOR_1: Color = Color(0.84, 0.38, 0.24, 1.0)
const PACKAGE_RIBBON_COLOR_2: Color = Color(0.26, 0.68, 0.42, 1.0)
const PACKAGE_RIBBON_COLOR_3: Color = Color(0.36, 0.44, 0.90, 1.0)

# 货物类型导出到编辑器中。
# setter 内统一做规范化并立即刷新表现，确保编辑器修改和运行时修改行为一致。
@export var cargo_type: String = DEFAULT_CARGO_TYPE:
	set(value):
		cargo_type = _normalize_cargo_type(value)
		_update_visual_state()

# 是否处于包装态。
# setter 直接刷新叠层显示，避免状态与视觉不同步。
@export var is_packaged: bool = false:
	set(value):
		is_packaged = value
		_update_visual_state()

# 所属世界引用，由外部放置或在 _ready() 时从 GM 获取。
var _world: World

# 当前登记在货物层中的网格坐标。
# 这个坐标是逻辑位置，global_position 则是当前显示位置。
var _registered_cell: Vector2i

# 当前节点是否已经登记到 world.cargo_layer。
# 用这个标记避免重复注册或错误注销。
var _is_registered_to_layer := false

# 当前进行中的移动补间。
# 货物的逻辑位置会先切换到目标格子，视觉位置再通过 tween 平滑追过去。
var _move_tween: Tween

# 记录该货物最近一次在哪个节拍被“结算/处理”。
# 用于避免同一节拍内重复处理。
var last_resolved_beat: int = -1
@onready var _sprite: Sprite2D = $Sprite2D

# 以下节点都是运行时动态创建的视觉叠层，用于在基础贴图上增加包装态效果。
var _package_fill: Polygon2D
var _package_border: Line2D
var _package_ribbon_horizontal: Line2D
var _package_ribbon_vertical: Line2D


func _ready() -> void:
	# 先确保叠层节点存在，再统一刷新外观。
	_ensure_package_overlay()
	_update_visual_state()

	# 如果外部还没有明确指定 world，则默认接入全局世界。
	if _world == null:
		_world = GM.world

	# 节点进入场景树后自动注册到货物层，确保逻辑层和场景中的节点一致。
	if not _is_registered_to_layer:
		_register_to_cargo_layer()


func _exit_tree() -> void:
	# 退出场景树时先终止动画，再从逻辑层移除自身，避免留下悬挂引用。
	_stop_move_tween()
	_unregister_from_cargo_layer()


func _register_to_cargo_layer() -> void:
	# 没有 world 就无法完成坐标换算和层注册，直接返回。
	if _world == null:
		return

	# 以当前场景位置为准，换算出所在格子并写入 cargo_layer。
	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.cargo_layer.set_cell(_registered_cell, self)

	# 注册后把显示位置强制吸附到格子中心，避免手动摆放带来的细小偏移。
	_stop_move_tween()
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_cargo_layer() -> void:
	# 只有已注册并且 world 有效时才需要注销。
	if not _is_registered_to_layer or _world == null:
		return

	# 只擦除“确实还是自己占用”的格子，避免误删其他对象后续写入的数据。
	if _world.cargo_layer.get_cell(_registered_cell) == self:
		_world.cargo_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func get_registered_cell() -> Vector2i:
	# 返回当前逻辑格子坐标，供外部系统读取。
	return _registered_cell


func was_resolved_on_beat(beat_index: int) -> bool:
	# 判断当前节拍是否已经处理过该货物。
	return last_resolved_beat == beat_index


func mark_resolved_on_beat(beat_index: int) -> void:
	# 记录本次处理发生的节拍序号。
	last_resolved_beat = beat_index


func place_at_cell(world: World, cell: Vector2i) -> void:
	# 外部直接指定世界与格子时，立即完成逻辑登记和显示对齐。
	# 这个接口适合生成货物或关卡初始化时使用。
	_world = world
	_registered_cell = cell
	_stop_move_tween()
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_world.cargo_layer.set_cell(_registered_cell, self)
	_is_registered_to_layer = true


func move_to_cell(target_cell: Vector2i) -> bool:
	# 没有关联世界时无法移动。
	if _world == null:
		return false

	# 某些情况下节点可能还没注册，这里先补一次注册流程。
	if not _is_registered_to_layer:
		_register_to_cargo_layer()

	if not _is_registered_to_layer:
		return false

	# 目标格就是当前位置时，视为成功，不重复处理。
	if target_cell == _registered_cell:
		return true

	# 目标格已被占用则不能移动。
	if _world.cargo_layer.has_cell(target_cell):
		return false

	# 当前登记格如果已经不是自己，说明逻辑层状态异常，直接 fail-fast。
	if _world.cargo_layer.get_cell(_registered_cell) != self:
		return false

	var target_global_position: Vector2 = _world.to_global(_world.cell_to_world(target_cell))

	# 先更新逻辑层占用，再启动视觉补间。
	# 这样其他系统在同一帧读取 cargo_layer 时，拿到的是最新逻辑位置。
	_world.cargo_layer.erase_cell(_registered_cell)
	_world.cargo_layer.set_cell(target_cell, self)
	_registered_cell = target_cell
	_start_move_to_global_position(target_global_position)
	return true


func remove_from_world() -> void:
	# 完整移除流程：停止动画、注销逻辑占用、释放节点。
	_stop_move_tween()
	_unregister_from_cargo_layer()
	queue_free()


func _start_move_to_global_position(target_global_position: Vector2) -> void:
	# 开始新移动前先清掉旧 tween，避免多个补间同时改同一属性。
	_stop_move_tween()

	# 已经在目标点时直接落位，不创建 tween。
	if global_position.is_equal_approx(target_global_position):
		global_position = target_global_position
		return

	var move_duration: float = _get_move_duration_seconds()

	# 节拍系统不可用或时长为 0 时，退化为瞬移。
	if move_duration <= 0.0:
		global_position = target_global_position
		return

	_move_tween = create_tween()
	var move_tweener: PropertyTweener = _move_tween.tween_property(self, "global_position", target_global_position, move_duration)
	move_tweener.set_trans(Tween.TRANS_LINEAR)
	_move_tween.finished.connect(_on_move_tween_finished)


func _get_move_duration_seconds() -> float:
	# beats 不存在时返回 0，让调用方自动走“直接落位”逻辑。
	if not is_instance_valid(GM.beats):
		return 0.0

	return maxf(GM.beats.get_beat_interval_seconds() * MOVE_DURATION_RATIO, 0.0)


func _stop_move_tween() -> void:
	# 统一停止并清空 tween 引用，避免悬挂回调。
	if not is_instance_valid(_move_tween):
		return

	_move_tween.kill()
	_move_tween = null


func _on_move_tween_finished() -> void:
	# tween 完成后清掉引用，表示当前没有活动中的移动动画。
	_move_tween = null


static func _normalize_cargo_type(value: Variant) -> String:
	# 统一去空白并转大写，降低外部传值格式不一致带来的分支复杂度。
	var normalized_value: String = String(value).strip_edges().to_upper()
	return normalized_value if not normalized_value.is_empty() else DEFAULT_CARGO_TYPE


func _update_visual_state() -> void:
	# _ready() 前 setter 也可能触发刷新，所以这里先判空。
	if _sprite == null:
		return

	# 货物贴图直接由当前类型决定，包装态通过额外叠层体现。
	_sprite.texture = _get_texture_for_type(cargo_type)
	_update_package_overlay()


func _get_texture_for_type(type_name: String) -> Texture2D:
	# 根据基础货物类型选择贴图。
	match type_name:
		"CARGO_2":
			return CARGO_TEXTURE_2
		"CARGO_3":
			return CARGO_TEXTURE_3
		_:
			return CARGO_TEXTURE_1


func _ensure_package_overlay() -> void:
	# 包装态相关节点也只创建一次，避免反复 new/free。
	if is_instance_valid(_package_fill):
		return

	# 包装层直接复用几何图形，避免新增贴图资源。
	_package_fill = Polygon2D.new()
	_package_fill.name = "PackageFill"
	_package_fill.z_index = 2
	_package_fill.polygon = PackedVector2Array([
		Vector2(14.0, 14.0),
		Vector2(50.0, 14.0),
		Vector2(50.0, 50.0),
		Vector2(14.0, 50.0),
	])
	add_child(_package_fill)

	_package_border = _create_package_line(
		"PackageBorder",
		PackedVector2Array([
			Vector2(14.0, 14.0),
			Vector2(50.0, 14.0),
			Vector2(50.0, 50.0),
			Vector2(14.0, 50.0),
			Vector2(14.0, 14.0),
		]),
		3.0
	)
	_package_border.z_index = 3
	add_child(_package_border)

	_package_ribbon_horizontal = _create_package_line(
		"PackageRibbonHorizontal",
		PackedVector2Array([
			Vector2(16.0, 32.0),
			Vector2(48.0, 32.0),
		]),
		4.0
	)
	_package_ribbon_horizontal.z_index = 4
	add_child(_package_ribbon_horizontal)

	_package_ribbon_vertical = _create_package_line(
		"PackageRibbonVertical",
		PackedVector2Array([
			Vector2(32.0, 16.0),
			Vector2(32.0, 48.0),
		]),
		4.0
	)
	_package_ribbon_vertical.z_index = 4
	add_child(_package_ribbon_vertical)


func _create_package_line(line_name: String, points: PackedVector2Array, width: float) -> Line2D:
	# 小工具函数：统一创建抗锯齿的线段节点，减少重复设置。
	var line: Line2D = Line2D.new()
	line.name = line_name
	line.points = points
	line.width = width
	line.antialiased = true
	return line


func _update_package_overlay() -> void:
	# 节点尚未创建时无需更新。
	if not is_instance_valid(_package_fill):
		return

	# 包装态开启时显示底色、边框和绑带；关闭时整体隐藏。
	var ribbon_color: Color = _get_package_ribbon_color()
	_package_fill.color = PACKAGE_FILL_COLOR
	_package_fill.visible = is_packaged
	_package_border.default_color = PACKAGE_BORDER_COLOR
	_package_border.visible = is_packaged
	_package_ribbon_horizontal.default_color = ribbon_color
	_package_ribbon_horizontal.visible = is_packaged
	_package_ribbon_vertical.default_color = ribbon_color
	_package_ribbon_vertical.visible = is_packaged


func _get_package_ribbon_color() -> Color:
	# 绑带颜色跟货物类型关联，方便快速识别来源。
	match cargo_type:
		"CARGO_2":
			return PACKAGE_RIBBON_COLOR_2
		"CARGO_3":
			return PACKAGE_RIBBON_COLOR_3
		_:
			return PACKAGE_RIBBON_COLOR_1
