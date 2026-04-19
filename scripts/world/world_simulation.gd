class_name WorldSimulation
extends RefCounted

const TRIGGERED_SORTERS_KEY: StringName = &"sorters"
const TRIGGERED_PRESS_MACHINES_KEY: StringName = &"press_machines"
const TRIGGERED_REFINERS_KEY: StringName = &"refiners"
const TRIGGERED_PACKERS_KEY: StringName = &"packers"

var _world: World


func _init(world: World) -> void:
	assert(world != null, "WorldSimulation requires a World instance.")
	_world = world


# 拍点触发时执行完整结算流程：产出、运输、打包、精炼、压制、回收。
func resolve_beat(beat_index: int, triggered_devices: Dictionary) -> void:
	# 单拍内按固定顺序结算，避免运输、加工、回收之间互相抢状态。
	var triggered_sorters: Dictionary = triggered_devices.get(TRIGGERED_SORTERS_KEY, {})
	var triggered_press_machines: Dictionary = triggered_devices.get(TRIGGERED_PRESS_MACHINES_KEY, {})
	var triggered_refiners: Dictionary = triggered_devices.get(TRIGGERED_REFINERS_KEY, {})
	var triggered_packers: Dictionary = triggered_devices.get(TRIGGERED_PACKERS_KEY, {})
	_resolve_producer_spawns(beat_index)
	_toggle_triggered_sorters(triggered_sorters)
	_resolve_transport(beat_index, triggered_press_machines)
	_resolve_packers(beat_index, triggered_packers)
	_resolve_refiners(beat_index, triggered_refiners)
	_resolve_press_machines(beat_index, triggered_press_machines)
	_resolve_recycler_collection()


# 按拍点让生产机尝试生成货物。
func _resolve_producer_spawns(beat_index: int) -> void:
	var producer_cells: Dictionary = _world.producer_layer.get_cells()

	for cell in producer_cells.keys():
		var producer: Producer = producer_cells[cell] as Producer
		if producer == null or not is_instance_valid(producer):
			continue

		if not producer.should_trigger_on_beat(beat_index):
			continue

		var target_cell: Vector2i = producer.get_target_cell()
		if _world.cargo_layer.has_cell(target_cell):
			continue

		_world.spawn_cargo(target_cell, producer.cargo_type)


# 汇总并执行本拍运输请求，先判定再统一处理冲突。
func _resolve_transport(beat_index: int, triggered_press_machines: Dictionary) -> void:
	# 先收集本拍所有运输请求，再统一裁决冲突，避免先后遍历顺序影响结果。
	var direct_requests: Array[Dictionary] = []
	var incoming_press_requests: Array[Dictionary] = []
	var occupied_cells: Dictionary = _world.cargo_layer.get_cells().duplicate()
	_collect_belt_requests(beat_index, occupied_cells, direct_requests, incoming_press_requests)
	_collect_sorter_requests(beat_index, occupied_cells, direct_requests, incoming_press_requests)
	_collect_idle_press_machine_requests(beat_index, triggered_press_machines, direct_requests)
	_resolve_simple_move_requests(direct_requests, beat_index, occupied_cells)
	_resolve_incoming_press_requests(incoming_press_requests, beat_index, triggered_press_machines)


# 收集传送带在当前拍内产生的移动请求，区分是否打到压机入口。
func _collect_belt_requests(beat_index: int, occupied_cells: Dictionary, direct_requests: Array[Dictionary], incoming_press_requests: Array[Dictionary]) -> void:
	var belt_cells: Dictionary = _world.belt_layer.get_cells()

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
		if _world.press_machine_layer.has_cell(target_cell):
			incoming_press_requests.append(request)
			continue

		direct_requests.append(request)


# 收集分拣机在当前拍内的输出请求，按目标分流直接移动或压机入口等待。
func _collect_sorter_requests(beat_index: int, occupied_cells: Dictionary, direct_requests: Array[Dictionary], incoming_press_requests: Array[Dictionary]) -> void:
	var sorter_cells: Dictionary = _world.sorter_layer.get_cells()

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
		if _world.press_machine_layer.has_cell(target_cell):
			incoming_press_requests.append(request)
			continue

		direct_requests.append(request)


# 收集空闲压机入口的待处理请求，避免与本拍已触发压机冲突。
func _collect_idle_press_machine_requests(beat_index: int, triggered_press_machines: Dictionary, direct_requests: Array[Dictionary]) -> void:
	var press_machine_cells: Dictionary = _world.press_machine_layer.get_cells()

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

		var cargo: Cargo = _world.cargo_layer.get_cell(cell) as Cargo
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
		var press_machine: PressMachine = _world.press_machine_layer.get_cell(cell) as PressMachine
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

		if _world.cargo_layer.has_cell(cell):
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

		if _world.cargo_layer.has_cell(target_cell):
			continue

		cargo.move_to_cell(target_cell)


# 处理精炼机在本拍内的状态转换与输出动作。
func _resolve_refiners(beat_index: int, triggered_refiners: Dictionary) -> void:
	var refiner_cells: Dictionary = _world.refiner_layer.get_cells()
	var output_requests: Array[Dictionary] = []
	var target_counts: Dictionary = {}

	for cell in refiner_cells.keys():
		var refiner: Refiner = refiner_cells[cell] as Refiner
		if refiner == null or not is_instance_valid(refiner):
			continue

		var did_trigger: bool = refiner.resolve_signal_state(beat_index, triggered_refiners.has(cell))
		if not did_trigger:
			continue

		var cargo: Cargo = _world.cargo_layer.get_cell(cell) as Cargo
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

		if _world.cargo_layer.has_cell(target_cell):
			continue

		cargo.move_to_cell(target_cell)


# 输出已完成压制的货物，并检查目标格冲突后清理压机状态。
func _resolve_finished_press_outputs(beat_index: int) -> void:
	var press_machine_cells: Dictionary = _world.press_machine_layer.get_cells()
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

		if _world.cargo_layer.has_cell(target_cell):
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

		var cargo: Cargo = _world.cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		press_machine.begin_press(cargo, beat_index)
		cargo.mark_resolved_on_beat(beat_index)


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
	var recycler_cells: Dictionary = _world.recycler_layer.get_cells()
	var did_progress: bool = false

	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		assert(recycler != null and is_instance_valid(recycler), "recycler_layer contains an invalid Recycler at %s." % [cell])

		var cargo: Cargo = _world.cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		if recycler.collect_cargo(cargo):
			did_progress = true

	# 只有本次确实发生回收进度时才检查胜利，避免无意义重复触发。
	if did_progress and _world.are_all_recyclers_completed():
		GM.finish_game(true)
