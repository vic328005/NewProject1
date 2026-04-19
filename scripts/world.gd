class_name World
extends Node2D

# 货物预制体模板，用于按格子动态创建货物实例。
const CARGO_SCENE: PackedScene = preload("res://prefabs/cargo.tscn")
# 环境预制体模板，用于加载世界基础场景。
const ENVIRONMENT_SCENE: PackedScene = preload("res://prefabs/environment.tscn")

# 主层：承载基础元胞网格逻辑与通用世界映射。
var main_layer: MapLayer
# 货物层：记录所有货物实例的占用与移动。
var cargo_layer: MapLayer
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
# 精炼机层：记录会转换货物类型的精炼器。
var refiner_layer: MapLayer
# 打包机层：记录会将货物推进行走位移的打包设备。
var packer_layer: MapLayer
# 世界环境节点，用于承载背景和装饰内容。
var environment: Node2D
# 当前关卡唯一标识。
var level_id: String = ""
# 当前关卡显示名称。
var display_name: String = ""
# 当前正在运行的信号波列表。
var _active_signals: Array = []
# 记录上次发射信号的拍点，防止同拍重复触发。
var _last_signal_emit_beat_index: int = -1
# 节拍器引用，负责监听拍点并驱动世界结算。
var _beats: BeatConductor
# 全局配置引用，用于层尺寸等参数初始化。
var _config: Config


# 初始化世界状态，注入配置并创建运行时层与环境节点。
func _init(config: Config) -> void:
	assert(config != null, "World requires a Config instance.")
	_config = config
	# 运行期图层在初始化时一次性建好，后续关卡切换只清内容不重建结构。
	main_layer = _create_layer()
	cargo_layer = _create_layer()
	belt_layer = _create_layer()
	sorter_layer = _create_layer()
	producer_layer = _create_layer()
	recycler_layer = _create_layer()
	signal_tower_layer = _create_layer()
	press_machine_layer = _create_layer()
	refiner_layer = _create_layer()
	packer_layer = _create_layer()
	_init_environment()


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
	# 只移除运行时关卡内容，保留 World 自身常驻节点与图层结构。
	for child in get_children():
		if child.is_in_group("runtime_level_content"):
			remove_child(child)
			child.queue_free()

	main_layer.clear()
	cargo_layer.clear()
	belt_layer.clear()
	sorter_layer.clear()
	producer_layer.clear()
	recycler_layer.clear()
	signal_tower_layer.clear()
	press_machine_layer.clear()
	refiner_layer.clear()
	packer_layer.clear()
	_active_signals.clear()
	_last_signal_emit_beat_index = -1
	level_id = ""
	display_name = ""


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
		if recycler == null or not is_instance_valid(recycler):
			continue

		total_required_count += recycler.required_count

	return total_required_count


# 统计回收机当前剩余需求总量，用于显示剩余目标。
func get_remaining_recycler_required_count() -> int:
	var remaining_required_count: int = 0
	var recycler_cells: Dictionary = recycler_layer.get_cells()
	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		if recycler == null or not is_instance_valid(recycler):
			continue

		remaining_required_count += recycler.get_remaining_count()

	return remaining_required_count


# 判断所有回收机是否都已完成回收目标。
func are_all_recyclers_completed() -> bool:
	var recycler_cells: Dictionary = recycler_layer.get_cells()
	if recycler_cells.is_empty():
		return false

	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		if recycler == null or not is_instance_valid(recycler):
			continue

		if not recycler.is_completed():
			return false

	return true


# 把节点标记为运行时关卡内容并挂到世界节点下。
func add_level_content(node: Node) -> void:
	node.add_to_group("runtime_level_content")
	add_child(node)


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


# 拍点触发时执行完整结算流程：产出、运输、打包、精炼、压制、回收、信号。
func _on_beat_fired(beat_index: int, _beat_time: float) -> void:
	# 单拍内按固定顺序结算，避免运输、加工、回收之间互相抢状态。
	var triggered_sorters: Dictionary = _collect_triggered_sorters()
	var triggered_press_machines: Dictionary = _collect_triggered_press_machines()
	var triggered_refiners: Dictionary = _collect_triggered_refiners()
	var triggered_packers: Dictionary = _collect_triggered_packers()
	_resolve_producer_spawns(beat_index)
	_toggle_triggered_sorters(triggered_sorters)
	_resolve_transport(beat_index, triggered_press_machines)
	_resolve_packers(beat_index, triggered_packers)
	_resolve_refiners(beat_index, triggered_refiners)
	_resolve_press_machines(beat_index, triggered_press_machines)
	_resolve_recycler_collection()
	_resolve_signals(beat_index)


# 在指定格子生成货物实例，失败时返回 null。
func spawn_cargo(cell: Vector2i, cargo_type: String) -> Cargo:
	# 同一格同一时刻只允许存在一个货物。
	if cargo_layer.has_cell(cell):
		return null

	var cargo: Cargo = CARGO_SCENE.instantiate() as Cargo
	cargo.cargo_type = cargo_type
	cargo.place_at_cell(self, cell)
	add_level_content(cargo)
	return cargo


# 按拍点让生产机尝试生成货物。
func _resolve_producer_spawns(beat_index: int) -> void:
	var producer_cells: Dictionary = producer_layer.get_cells()

	for cell in producer_cells.keys():
		var producer: Producer = producer_cells[cell] as Producer
		if producer == null or not is_instance_valid(producer):
			continue

		if not producer.should_trigger_on_beat(beat_index):
			continue

		var target_cell: Vector2i = producer.get_target_cell()
		if cargo_layer.has_cell(target_cell):
			continue

		spawn_cargo(target_cell, producer.cargo_type)


# 汇总并执行本拍运输请求，先判定再统一处理冲突。
func _resolve_transport(beat_index: int, triggered_press_machines: Dictionary) -> void:
	# 先收集本拍所有运输请求，再统一裁决冲突，避免先后遍历顺序影响结果。
	var direct_requests: Array[Dictionary] = []
	var incoming_press_requests: Array[Dictionary] = []
	var occupied_cells: Dictionary = cargo_layer.get_cells().duplicate()
	_collect_belt_requests(beat_index, occupied_cells, direct_requests, incoming_press_requests)
	_collect_sorter_requests(beat_index, occupied_cells, direct_requests, incoming_press_requests)
	_collect_idle_press_machine_requests(beat_index, triggered_press_machines, direct_requests)
	_resolve_simple_move_requests(direct_requests, beat_index, occupied_cells)
	_resolve_incoming_press_requests(incoming_press_requests, beat_index, triggered_press_machines)


# 收集传送带在当前拍内产生的移动请求，区分是否打到压机入口。
func _collect_belt_requests(beat_index: int, occupied_cells: Dictionary, direct_requests: Array[Dictionary], incoming_press_requests: Array[Dictionary]) -> void:
	var belt_cells: Dictionary = belt_layer.get_cells()

	for cell in belt_cells.keys():
		var belt: Belt = belt_cells[cell] as Belt
		if belt == null or not is_instance_valid(belt):
			continue

		if not belt.should_trigger_on_beat(beat_index):
			continue

		var cargo: Cargo = occupied_cells.get(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		if cargo.was_resolved_on_beat(beat_index):
			continue

		var request: Dictionary = {
			"cargo": cargo,
			"target_cell": belt.get_target_cell(),
		}
		var target_cell: Vector2i = request["target_cell"]
		if press_machine_layer.has_cell(target_cell):
			incoming_press_requests.append(request)
			continue

		direct_requests.append(request)


# 收集分拣机在当前拍内的输出请求，按目标分流直接移动或压机入口等待。
func _collect_sorter_requests(beat_index: int, occupied_cells: Dictionary, direct_requests: Array[Dictionary], incoming_press_requests: Array[Dictionary]) -> void:
	var sorter_cells: Dictionary = sorter_layer.get_cells()

	for cell in sorter_cells.keys():
		var sorter: Sorter = sorter_cells[cell] as Sorter
		if sorter == null or not is_instance_valid(sorter):
			continue

		if not sorter.should_trigger_on_beat(beat_index):
			continue

		var cargo: Cargo = occupied_cells.get(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		if cargo.was_resolved_on_beat(beat_index):
			continue

		var request: Dictionary = {
			"cargo": cargo,
			"target_cell": sorter.get_target_cell(),
		}
		var target_cell: Vector2i = request["target_cell"]
		if press_machine_layer.has_cell(target_cell):
			incoming_press_requests.append(request)
			continue

		direct_requests.append(request)


# 收集空闲压机入口的待处理请求，避免与本拍已触发压机冲突。
func _collect_idle_press_machine_requests(beat_index: int, triggered_press_machines: Dictionary, direct_requests: Array[Dictionary]) -> void:
	var press_machine_cells: Dictionary = press_machine_layer.get_cells()

	for cell in press_machine_cells.keys():
		var press_machine: PressMachine = press_machine_cells[cell] as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if press_machine.is_pressing():
			continue

		if not press_machine.should_trigger_on_beat(beat_index):
			continue

		if _is_press_machine_triggered(press_machine, triggered_press_machines):
			continue

		var cargo: Cargo = cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		if cargo.was_resolved_on_beat(beat_index):
			continue

		direct_requests.append({
			"cargo": cargo,
			"target_cell": press_machine.get_target_cell(),
		})


# 执行基础移动请求，目标冲突时不移动但仍标记本拍已处理。
func _resolve_simple_move_requests(requests: Array[Dictionary], beat_index: int, occupied_cells: Dictionary) -> void:
	var target_counts: Dictionary = {}
	for request in requests:
		var target_cell: Vector2i = request["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in requests:
		var cargo: Cargo = request["cargo"] as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.mark_resolved_on_beat(beat_index)

		var target_cell: Vector2i = request["target_cell"]
		# 多个货物争同一目标格时，本拍全部不移动，但仍视为已参与过结算。
		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if occupied_cells.has(target_cell):
			continue

		cargo.move_to_cell(target_cell)


# 处理朝向压机入口的请求：忙碌、冲突、占用和成功进入压机均分情况处理。
func _resolve_incoming_press_requests(incoming_press_requests: Array[Dictionary], beat_index: int, triggered_press_machines: Dictionary) -> void:
	var requests_by_cell: Dictionary = {}
	for request in incoming_press_requests:
		var target_cell: Vector2i = request["target_cell"]
		if not requests_by_cell.has(target_cell):
			requests_by_cell[target_cell] = []

		var requests_at_cell: Array = requests_by_cell[target_cell]
		requests_at_cell.append(request)
		requests_by_cell[target_cell] = requests_at_cell

	for cell in requests_by_cell.keys():
		var press_machine: PressMachine = press_machine_layer.get_cell(cell) as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		var requests_at_cell: Array = requests_by_cell[cell]
		if press_machine.is_pressing():
			# 冲床忙碌时，撞入的货物直接销毁，体现“压机入口不可堆积”的规则。
			for request in requests_at_cell:
				var busy_cargo: Cargo = request["cargo"] as Cargo
				if busy_cargo == null or not is_instance_valid(busy_cargo):
					continue

				busy_cargo.mark_resolved_on_beat(beat_index)
				busy_cargo.remove_from_world()

			continue

		if requests_at_cell.size() != 1:
			for request in requests_at_cell:
				var blocked_cargo: Cargo = request["cargo"] as Cargo
				if blocked_cargo == null or not is_instance_valid(blocked_cargo):
					continue

				blocked_cargo.mark_resolved_on_beat(beat_index)

			continue

		if cargo_layer.has_cell(cell):
			var occupied_cargo: Cargo = requests_at_cell[0]["cargo"] as Cargo
			if occupied_cargo != null and is_instance_valid(occupied_cargo):
				occupied_cargo.mark_resolved_on_beat(beat_index)

			continue

		var request: Dictionary = requests_at_cell[0]
		var cargo: Cargo = request["cargo"] as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.mark_resolved_on_beat(beat_index)

		if _is_press_machine_triggered(press_machine, triggered_press_machines):
			cargo.move_to_cell(cell)
			continue

		cargo.move_to_cell(cell)


# 先结算已完成压机输出，再启动新一轮被信号触发的压制。
func _resolve_press_machines(beat_index: int, triggered_press_machines: Dictionary) -> void:
	# 先吐出上一轮压制结果，再开始新的压制，保证状态切换清晰。
	_resolve_finished_press_outputs(beat_index)
	_start_triggered_presses(beat_index, triggered_press_machines)


# 处理打包机动作：标记已打包并尝试按目标格移动。
func _resolve_packers(beat_index: int, triggered_packers: Dictionary) -> void:
	var output_requests: Array[Dictionary] = []
	var target_counts: Dictionary = {}

	for cell in triggered_packers.keys():
		var packer_state: Dictionary = triggered_packers[cell]
		var packer: Packer = packer_state.get("packer") as Packer
		var cargo: Cargo = packer_state.get("cargo") as Cargo
		if packer == null or not is_instance_valid(packer):
			continue

		if cargo == null or not is_instance_valid(cargo):
			continue

		if cargo.get_registered_cell() != packer.get_registered_cell():
			continue

		var target_cell: Vector2i = packer.get_target_cell()
		output_requests.append({
			"cargo": cargo,
			"target_cell": target_cell,
		})

		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in output_requests:
		var cargo: Cargo = request["cargo"] as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.is_packaged = true
		cargo.mark_resolved_on_beat(beat_index)

		var target_cell: Vector2i = request["target_cell"]
		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if cargo_layer.has_cell(target_cell):
			continue

		cargo.move_to_cell(target_cell)


# 处理精炼机在本拍内的状态转换与输出动作。
func _resolve_refiners(beat_index: int, triggered_refiners: Dictionary) -> void:
	var refiner_cells: Dictionary = refiner_layer.get_cells()
	var output_requests: Array[Dictionary] = []
	var target_counts: Dictionary = {}

	for cell in refiner_cells.keys():
		var refiner: Refiner = refiner_cells[cell] as Refiner
		if refiner == null or not is_instance_valid(refiner):
			continue

		var did_trigger: bool = refiner.resolve_signal_state(beat_index, triggered_refiners.has(cell))
		if not did_trigger:
			continue

		var cargo: Cargo = cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.cargo_type = refiner.get_refined_cargo_type(cargo.cargo_type)
		var target_cell: Vector2i = refiner.get_target_cell()
		output_requests.append({
			"cargo": cargo,
			"target_cell": target_cell,
		})

		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in output_requests:
		var cargo: Cargo = request["cargo"] as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.mark_resolved_on_beat(beat_index)

		var target_cell: Vector2i = request["target_cell"]
		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if cargo_layer.has_cell(target_cell):
			continue

		cargo.move_to_cell(target_cell)


# 输出已完成压制的货物，并检查目标格冲突后清理压机状态。
func _resolve_finished_press_outputs(beat_index: int) -> void:
	var press_machine_cells: Dictionary = press_machine_layer.get_cells()
	var output_requests: Array[Dictionary] = []
	var target_counts: Dictionary = {}

	for cell in press_machine_cells.keys():
		var press_machine: PressMachine = press_machine_cells[cell] as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if not press_machine.has_finished_press(beat_index):
			continue

		if not press_machine.should_trigger_on_beat(beat_index):
			continue

		var cargo: Cargo = press_machine.get_pressed_cargo()
		if cargo == null or not is_instance_valid(cargo):
			press_machine.clear_pressed_cargo()
			continue

		cargo.cargo_type = press_machine.cargo_type
		var target_cell: Vector2i = press_machine.get_target_cell()
		output_requests.append({
			"cargo": cargo,
			"target_cell": target_cell,
			"press_machine": press_machine,
		})
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in output_requests:
		var press_machine: PressMachine = request["press_machine"] as PressMachine
		var cargo: Cargo = request["cargo"] as Cargo
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if cargo == null or not is_instance_valid(cargo):
			press_machine.clear_pressed_cargo()
			continue

		cargo.mark_resolved_on_beat(beat_index)

		var target_cell: Vector2i = request["target_cell"]
		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if cargo_layer.has_cell(target_cell):
			continue

		if not cargo.move_to_cell(target_cell):
			continue

		press_machine.clear_pressed_cargo()


# 对当前拍内被触发且可用的压机开始压制输入货物。
func _start_triggered_presses(beat_index: int, triggered_press_machines: Dictionary) -> void:
	for cell in triggered_press_machines.keys():
		var press_machine: PressMachine = triggered_press_machines[cell] as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if press_machine.is_pressing():
			continue

		var cargo: Cargo = cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		press_machine.begin_press(cargo, beat_index)
		cargo.mark_resolved_on_beat(beat_index)


# 收集当前生效信号波命中的分拣机，仅保留同一拍有效目标。
func _collect_triggered_sorters() -> Dictionary:
	var triggered_sorters: Dictionary = {}

	# 信号波按覆盖到的格子触发设备，设备类型各自独立收集。
	for signal_wave_node in _active_signals:
		var signal_wave: SignalWave = signal_wave_node as SignalWave
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var sorter: Sorter = sorter_layer.get_cell(cell) as Sorter
			if sorter == null or not is_instance_valid(sorter):
				continue

			triggered_sorters[cell] = sorter

	return triggered_sorters


# 收集当前生效信号波命中的压机节点。
func _collect_triggered_press_machines() -> Dictionary:
	var triggered_press_machines: Dictionary = {}

	for signal_wave_node in _active_signals:
		var signal_wave: SignalWave = signal_wave_node as SignalWave
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var press_machine: PressMachine = press_machine_layer.get_cell(cell) as PressMachine
			if press_machine == null or not is_instance_valid(press_machine):
				continue

			triggered_press_machines[cell] = press_machine

	return triggered_press_machines


# 收集当前生效信号波命中的精炼机节点。
func _collect_triggered_refiners() -> Dictionary:
	var triggered_refiners: Dictionary = {}

	for signal_wave_node in _active_signals:
		var signal_wave: SignalWave = signal_wave_node as SignalWave
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var refiner: Refiner = refiner_layer.get_cell(cell) as Refiner
			if refiner == null or not is_instance_valid(refiner):
				continue

			triggered_refiners[cell] = refiner

	return triggered_refiners


# 收集当前生效信号波命中的打包机及当拍初始货物快照。
func _collect_triggered_packers() -> Dictionary:
	var triggered_packers: Dictionary = {}

	for signal_wave_node in _active_signals:
		var signal_wave: SignalWave = signal_wave_node as SignalWave
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var packer: Packer = packer_layer.get_cell(cell) as Packer
			if packer == null or not is_instance_valid(packer):
				continue

			# 这里记录信号命中当下的货物快照，避免同拍后续运输把新货送进来后被误打包。
			triggered_packers[cell] = {
				"packer": packer,
				"cargo": cargo_layer.get_cell(cell) as Cargo,
			}

	return triggered_packers


# 按触发结果切换分拣机的输出方向/状态。
func _toggle_triggered_sorters(triggered_sorters: Dictionary) -> void:
	for cell in triggered_sorters.keys():
		var sorter: Sorter = triggered_sorters[cell] as Sorter
		if sorter == null or not is_instance_valid(sorter):
			continue

		sorter.toggle_output()


# 判断某台压机是否被当前信号波命中触发。
func _is_press_machine_triggered(press_machine: PressMachine, triggered_press_machines: Dictionary) -> bool:
	if press_machine == null or not is_instance_valid(press_machine):
		return false

	return triggered_press_machines.has(press_machine.get_registered_cell())


# 处理所有回收机的回收进度，并在全部达成时结束关卡。
func _resolve_recycler_collection() -> void:
	var recycler_cells: Dictionary = recycler_layer.get_cells()
	var did_progress: bool = false

	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		if recycler == null or not is_instance_valid(recycler):
			continue

		var cargo: Cargo = cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		if recycler.collect_cargo(cargo):
			did_progress = true

	# 只有本次确实发生回收进度时才检查胜利，避免无意义重复触发。
	if did_progress and are_all_recyclers_completed():
		GM.finish_game(true)


# 推进当前拍的信号波前进并清理完成的波。
func _resolve_signals(beat_index: int) -> void:
	for index in range(_active_signals.size() - 1, -1, -1):
		var signal_wave: SignalWave = _active_signals[index] as SignalWave
		if signal_wave == null or not is_instance_valid(signal_wave):
			_active_signals.remove_at(index)
			continue

		signal_wave.advance(beat_index)
		if not signal_wave.is_finished():
			continue

		_active_signals.remove_at(index)
		signal_wave.remove_from_world()


# 按当前拍向全场信号塔尝试发射信号，单拍只允许一次发射。
func try_emit_signal_towers_for_current_beat() -> bool:
	var current_beat_index: int = 0
	if is_instance_valid(_beats):
		current_beat_index = _beats.get_current_beat_index()

	# 同一拍只允许发射一次，避免重复点击或多处调用叠加出额外信号波。
	if current_beat_index == _last_signal_emit_beat_index:
		return false

	var emitted: bool = false
	var signal_tower_cells: Dictionary = signal_tower_layer.get_cells()
	for cell in signal_tower_cells.keys():
		var signal_tower: SignalTower = signal_tower_cells[cell] as SignalTower
		if signal_tower == null or not is_instance_valid(signal_tower):
			continue

		var signal_wave: SignalWave = signal_tower.create_signal_wave(current_beat_index)
		_active_signals.append(signal_wave)
		add_level_content(signal_wave)
		emitted = true

	if not emitted:
		return false

	_last_signal_emit_beat_index = current_beat_index
	return true
