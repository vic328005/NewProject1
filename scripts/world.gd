class_name World
extends Node2D

# 货物预制体模板，用于按格子动态创建货物实例。
const CARGO_SCENE: PackedScene = preload("res://prefabs/cargo.tscn")
# 产品预制体模板，用于按格子动态创建产品实例。
const PRODUCT_SCENE: PackedScene = preload("res://prefabs/product.tscn")
# 环境预制体模板，用于加载世界基础场景。
const ENVIRONMENT_SCENE: PackedScene = preload("res://prefabs/environment.tscn")

# 主层：承载基础元胞网格逻辑与通用世界映射。
var main_layer: MapLayer
# 运输物层：记录所有 cargo / product 实例的占用与移动。
var item_layer: MapLayer
# 传送带层：处理有序运输设备的每拍行为。
var belt_layer: MapLayer
# 分拣机层：记录按信号触发的分拣节点状态。
var sorter_layer: MapLayer
# 生产机层：记录生成货物的设备。
var producer_layer: MapLayer
# 回收机层：记录回收目标与进度。
var recycler_layer: MapLayer
# 信号塔层：记录可发射信号波的塔。
var signal_tower_layer: MapLayer
# 冲压机层：记录会压制/输出货物的机器。
var press_machine_layer: MapLayer
# 打包机层：记录会将货物推进行走位移的打包设备。
var packer_layer: MapLayer
# 世界环境节点，用于承载背景和装饰内容。
var environment: Node2D
# 当前关卡唯一标识。
var level_id: String = ""
# 当前关卡显示名称。
var display_name: String = ""
# 节拍器引用，负责监听拍点并驱动世界结算。
var _beats: BeatConductor
# 全局配置引用，用于层尺寸等参数初始化。
var _config: Config
var _signal_system: WorldSignalSystem
var _simulation: WorldSimulation


# 初始化世界状态，注入配置并创建运行时层、环境和结算系统。
func _init(config: Config) -> void:
	assert(config != null, "World requires a Config instance.")
	_config = config
	_init_layers()
	_init_environment()
	_signal_system = WorldSignalSystem.new(self)
	_simulation = WorldSimulation.new(self)


# 节点进入场景树时注册当前世界实例。
func _enter_tree() -> void:
	GM.world = self


# 节点准备完成时绑定拍点事件，开始接收节拍广播。
func _ready() -> void:
	_beats = GM.beats
	if not _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.connect(_on_beat_fired)


# 节点退出场景树时断开拍点订阅并清理全局引用。
func _exit_tree() -> void:
	if is_instance_valid(_beats) and _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.disconnect(_on_beat_fired)

	if GM.world == self:
		GM.world = null


# 将世界坐标转换为主网格的格子坐标。
func world_to_cell(world_position: Vector2) -> Vector2i:
	return main_layer.world_to_cell(world_position)


# 将格子坐标转换为世界坐标。
func cell_to_world(cell: Vector2i) -> Vector2:
	return main_layer.cell_to_world(cell)


# 清空关卡运行态内容与运行状态，保留层结构用于下一关复用。
func clear_level_content() -> void:
	_clear_runtime_level_content()
	_clear_layers()
	_clear_runtime_state()


# 将关卡元数据写入世界状态（ID、名称）。
func apply_level_metadata(level_data: LevelData) -> void:
	level_id = level_data.level_id
	display_name = level_data.display_name


# 统计当前关卡所有回收机的目标回收总量。
func get_total_recycler_required_count() -> int:
	var total_required_count: int = 0
	var recycler_cells: Dictionary = recycler_layer.get_cells()
	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		assert(recycler != null and is_instance_valid(recycler), "recycler_layer contains an invalid Recycler at %s." % [cell])
		total_required_count += recycler.get_total_required_count()

	return total_required_count


# 统计回收机当前剩余需求总量，用于显示剩余目标。
func get_remaining_recycler_required_count() -> int:
	var remaining_required_count: int = 0
	var recycler_cells: Dictionary = recycler_layer.get_cells()
	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		assert(recycler != null and is_instance_valid(recycler), "recycler_layer contains an invalid Recycler at %s." % [cell])

		remaining_required_count += recycler.get_remaining_total_count()

	return remaining_required_count


# 判断所有回收机是否都已完成回收目标。
func are_all_recyclers_completed() -> bool:
	var recycler_cells: Dictionary = recycler_layer.get_cells()
	if recycler_cells.is_empty():
		return false

	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		assert(recycler != null and is_instance_valid(recycler), "recycler_layer contains an invalid Recycler at %s." % [cell])

		if not recycler.is_completed():
			return false

	return true


# 把节点标记为运行时关卡内容并挂到世界节点下。
func add_level_content(node: Node) -> void:
	node.add_to_group("runtime_level_content")
	add_child(node)


# 在指定格子生成货物实例，失败时返回 null。
func spawn_cargo(cell: Vector2i, cargo_type: String) -> Cargo:
	if item_layer.has_cell(cell):
		return null

	var cargo: Cargo = CARGO_SCENE.instantiate() as Cargo
	cargo.cargo_type = cargo_type
	cargo.place_at_cell(self, cell)
	add_level_content(cargo)
	return cargo


# 在指定格子生成产品实例，失败时返回 null。
func spawn_product(cell: Vector2i, product_type: String) -> Product:
	if item_layer.has_cell(cell):
		return null

	var product: Product = PRODUCT_SCENE.instantiate() as Product
	product.product_type = product_type
	product.place_at_cell(self, cell)
	add_level_content(product)
	return product


func get_transport_item(cell: Vector2i) -> TransportItem:
	return item_layer.get_cell(cell) as TransportItem


# 拍点触发时先固定本拍信号快照，再执行完整结算流程。
func _on_beat_fired(beat_index: int, _beat_time: float) -> void:
	# World 只负责编排顺序，具体规则交给独立系统处理。
	var signal_snapshot: Dictionary = _signal_system.begin_beat(beat_index)
	_simulation.resolve_beat(beat_index, signal_snapshot)


# 按当前拍向全场信号塔尝试发射信号，单拍只允许一次发射。
func try_emit_signal_towers_for_current_beat() -> bool:
	return _signal_system.try_emit_for_current_beat()


# 初始化所有运行时图层，后续关卡切换只清内容不重建结构。
func _init_layers() -> void:
	main_layer = _create_layer()
	item_layer = _create_layer()
	belt_layer = _create_layer()
	sorter_layer = _create_layer()
	producer_layer = _create_layer()
	recycler_layer = _create_layer()
	signal_tower_layer = _create_layer()
	press_machine_layer = _create_layer()
	packer_layer = _create_layer()


# 清空所有运行时图层。
func _clear_layers() -> void:
	main_layer.clear()
	item_layer.clear()
	belt_layer.clear()
	sorter_layer.clear()
	producer_layer.clear()
	recycler_layer.clear()
	signal_tower_layer.clear()
	press_machine_layer.clear()
	packer_layer.clear()


# 只移除运行时关卡内容，保留 World 自身常驻节点与结构。
func _clear_runtime_level_content() -> void:
	for child in get_children():
		if child.is_in_group("runtime_level_content"):
			remove_child(child)
			child.queue_free()


# 清空关卡级的瞬时状态，供下一关复用。
func _clear_runtime_state() -> void:
	if _signal_system != null:
		_signal_system.clear()

	level_id = ""
	display_name = ""


# 创建并挂载环境实例，用于承载非玩法实体。
func _init_environment() -> void:
	environment = ENVIRONMENT_SCENE.instantiate() as Node2D
	assert(environment != null, "Environment scene root must be a Node2D.")
	environment.name = "Environment"
	add_child(environment)


# 创建一个默认配置的 MapLayer 实例。
func _create_layer() -> MapLayer:
	var layer: MapLayer = MapLayer.new()
	layer.cell_size = _config.cell_size
	return layer
