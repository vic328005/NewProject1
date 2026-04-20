## 负责单个拍点内的世界结算。
## 这个类只做“读拍初快照 -> 生成计划 -> 分阶段提交”的编排，
## 具体机器和物体行为由各自节点实现。
class_name WorldSimulation
extends RefCounted

## 信号快照中记录本拍触发压塑机的字典键。
const TRIGGERED_PRESS_MACHINES_KEY: StringName = &"press_machines"
## 信号快照中记录本拍触发打包机的字典键。
const TRIGGERED_PACKERS_KEY: StringName = &"packers"

## 运输指令类型：本拍不移动，保持原地。
const ITEM_COMMAND_WAIT: StringName = &"WAIT"
## 运输指令类型：尝试移动到目标格。
const ITEM_COMMAND_MOVE_TO_CELL: StringName = &"MOVE_TO_CELL"

var _world: World


## 绑定要结算的世界实例。
## `world` 为硬依赖，缺失时直接中断，避免后续结算在空引用上继续。
func _init(world: World) -> void:
	assert(world != null, "WorldSimulation requires a World instance.")
	_world = world


## 执行一次完整拍点结算。
## 结算顺序固定为：生成快照 -> 出料 -> 运输 -> 入机/回收 -> 开始新周期。
## 这样可以保证本拍的判定只依赖拍初状态和本拍信号，避免同拍连锁影响语义。
func resolve_beat(beat_index: int, signal_snapshot: Dictionary) -> void:
	var beat_snapshot: Dictionary = _create_beat_snapshot(beat_index, signal_snapshot)
	var item_ids: Dictionary = _collect_item_ids(beat_snapshot["items"])
	_apply_output_phase(beat_index)
	var transport_commands: Dictionary = _create_transport_commands(beat_snapshot)
	var transport_snapshot_items: Dictionary = _world.item_layer.get_cells().duplicate()
	var move_success_by_id: Dictionary = _resolve_move_successes(transport_snapshot_items, transport_commands)
	_apply_transport_phase(beat_index, transport_commands, move_success_by_id)
	var did_recycler_progress: bool = _apply_input_phase(beat_index, beat_snapshot, item_ids)
	_apply_start_phase(beat_index, beat_snapshot)

	if did_recycler_progress and _world.are_all_recyclers_completed():
		GM.finish_game(true)


## 生成本拍统一使用的静态快照。
## 快照只记录拍初物体和本拍信号触发结果，后续阶段即使世界状态变化，也不回写这里。
func _create_beat_snapshot(beat_index: int, signal_snapshot: Dictionary) -> Dictionary:
	return {
		"beat_index": beat_index,
		"items": _world.item_layer.get_cells().duplicate(),
		"triggered_press_machines": signal_snapshot.get(TRIGGERED_PRESS_MACHINES_KEY, {}),
		"triggered_packers": signal_snapshot.get(TRIGGERED_PACKERS_KEY, {}),
	}


## 收集拍初参与运输结算的物体实例 ID。
## 后续输入阶段据此限制只处理拍初已有物体，避免新生成物体在同拍再次参与交互。
func _collect_item_ids(items: Dictionary) -> Dictionary:
	var item_ids: Dictionary = {}
	for item in items.values():
		var transport_item: Item = item as Item
		if transport_item == null or not is_instance_valid(transport_item):
			continue

		item_ids[transport_item.get_instance_id()] = true

	return item_ids


## 为拍初每个可运输物体生成本拍运输指令。
## 指令只描述“想做什么”，真正是否能移动要等冲突解析阶段统一决定。
func _create_transport_commands(beat_snapshot: Dictionary) -> Dictionary:
	var item_commands: Dictionary = {}
	var items: Dictionary = beat_snapshot["items"]

	for cell in items.keys():
		var item: Item = items[cell] as Item
		if item == null or not is_instance_valid(item):
			continue

		item_commands[item.get_instance_id()] = _create_transport_command(cell, item, beat_snapshot)

	return item_commands


## 根据物体所在格子的机器类型与本拍触发状态，生成单个物体的运输意图。
## 优先级体现格子交互语义：压塑机/打包机直通，其次传送带，最后停留。
func _create_transport_command(cell: Vector2i, item: Item, beat_snapshot: Dictionary) -> Dictionary:
	var triggered_press_machines: Dictionary = beat_snapshot["triggered_press_machines"]
	var press_machine: PressMachine = _world.press_machine_layer.get_cell(cell) as PressMachine
	if press_machine != null and is_instance_valid(press_machine) and press_machine.allows_pass_through(item, triggered_press_machines.has(cell), int(beat_snapshot["beat_index"])):
		return _create_move_command(item, cell, press_machine.get_target_cell(), {})

	var triggered_packers: Dictionary = beat_snapshot["triggered_packers"]
	var packer: Packer = _world.packer_layer.get_cell(cell) as Packer
	if packer != null and is_instance_valid(packer) and packer.allows_pass_through(item, triggered_packers.has(cell)):
		return _create_move_command(item, cell, packer.get_target_cell(), {})

	var beat_index: int = int(beat_snapshot["beat_index"])
	var belt: Belt = _world.belt_layer.get_cell(cell) as Belt
	if belt != null and is_instance_valid(belt) and belt.should_trigger_on_beat(beat_index):
		return _create_move_command(item, cell, belt.get_target_cell(), {})

	var recycler: Recycler = _world.recycler_layer.get_cell(cell) as Recycler
	if recycler != null and is_instance_valid(recycler):
		return _create_wait_command(item, cell)

	return _create_wait_command(item, cell)


## 构造“原地等待”运输指令。
func _create_wait_command(item: Item, from_cell: Vector2i) -> Dictionary:
	return _create_command(ITEM_COMMAND_WAIT, item, from_cell, {})


## 构造“移动到目标格”运输指令。
func _create_move_command(item: Item, from_cell: Vector2i, target_cell: Vector2i, extra_data: Dictionary) -> Dictionary:
	var command: Dictionary = _create_command(ITEM_COMMAND_MOVE_TO_CELL, item, from_cell, extra_data)
	command["target_cell"] = target_cell
	return command


## 构造通用运输指令字典。
## 基础字段统一放在这里，额外字段由调用方追加，避免不同指令格式分散。
func _create_command(command_type: StringName, item: Item, from_cell: Vector2i, extra_data: Dictionary) -> Dictionary:
	var command: Dictionary = {
		"type": command_type,
		"item": item,
		"from_cell": from_cell,
	}

	for key in extra_data.keys():
		command[key] = extra_data[key]

	return command


## 统一解析所有移动指令是否能成功。
## 这里会先按目标格聚合，再递归判断“目标格占用者是否会释放”，从而支持整条运输链同时前进。
func _resolve_move_successes(snapshot_items: Dictionary, item_commands: Dictionary) -> Dictionary:
	var move_success_by_id: Dictionary = {}
	var target_to_item_ids: Dictionary = {}

	for item_id in item_commands.keys():
		var command: Dictionary = item_commands[item_id]
		if not _is_move_command(command["type"]):
			continue

		var target_cell: Vector2i = command["target_cell"]
		if not target_to_item_ids.has(target_cell):
			target_to_item_ids[target_cell] = []

		var item_ids: Array = target_to_item_ids[target_cell]
		item_ids.append(item_id)
		target_to_item_ids[target_cell] = item_ids

	var resolve_states: Dictionary = {}
	# 逐个求值，但实际结果会通过递归缓存复用。
	for item_id in item_commands.keys():
		var command: Dictionary = item_commands[item_id]
		if not _is_move_command(command["type"]):
			continue

		move_success_by_id[item_id] = _resolve_move_success(
			int(item_id),
			snapshot_items,
			item_commands,
			target_to_item_ids,
			resolve_states,
			move_success_by_id
		)

	return move_success_by_id


## 递归判断单个移动指令是否成功。
## 规则：
## 1. 多个物体争抢同一目标格时全部失败。
## 2. 目标格为空时成功。
## 3. 目标格被占用时，只有占用者本拍也能成功移走，当前物体才成功。
## `resolve_states` 用于打断环形依赖，避免递归死循环。
func _resolve_move_success(item_id: int, snapshot_items: Dictionary, item_commands: Dictionary, target_to_item_ids: Dictionary, resolve_states: Dictionary, move_success_by_id: Dictionary) -> bool:
	if move_success_by_id.has(item_id):
		return bool(move_success_by_id[item_id])

	var resolve_state: int = int(resolve_states.get(item_id, 0))
	if resolve_state == 1:
		# 说明当前递归链再次访问到自己，形成闭环，本次移动视为失败。
		return false

	resolve_states[item_id] = 1

	var command: Dictionary = item_commands[item_id]
	var target_cell: Vector2i = command["target_cell"]
	var incoming_item_ids: Array = target_to_item_ids.get(target_cell, [])
	if incoming_item_ids.size() != 1:
		# 同一目标格存在竞争时，不做优先级仲裁，统一失败。
		move_success_by_id[item_id] = false
		resolve_states[item_id] = 2
		return false

	var target_occupant: Item = snapshot_items.get(target_cell) as Item
	if target_occupant == null or not is_instance_valid(target_occupant):
		move_success_by_id[item_id] = true
		resolve_states[item_id] = 2
		return true

	if target_occupant.get_instance_id() == item_id:
		move_success_by_id[item_id] = false
		resolve_states[item_id] = 2
		return false

	var can_release_target_cell: bool = _will_cell_be_released(
		target_cell,
		snapshot_items,
		item_commands,
		target_to_item_ids,
		resolve_states,
		move_success_by_id
	)
	move_success_by_id[item_id] = can_release_target_cell
	resolve_states[item_id] = 2
	return can_release_target_cell


## 判断某个格子在本拍运输结束后是否会被腾空。
## 如果占用者没有运输指令，或其运输指令本身失败，则该格子视为不会释放。
func _will_cell_be_released(cell: Vector2i, snapshot_items: Dictionary, item_commands: Dictionary, target_to_item_ids: Dictionary, resolve_states: Dictionary, move_success_by_id: Dictionary) -> bool:
	var occupant: Item = snapshot_items.get(cell) as Item
	if occupant == null or not is_instance_valid(occupant):
		return true

	var occupant_id: int = occupant.get_instance_id()
	if not item_commands.has(occupant_id):
		return false

	var occupant_command: Dictionary = item_commands[occupant_id]
	var occupant_command_type: StringName = occupant_command["type"]
	if not _is_move_command(occupant_command_type):
		return false

	return _resolve_move_success(
		occupant_id,
		snapshot_items,
		item_commands,
		target_to_item_ids,
		resolve_states,
		move_success_by_id
	)


## 提交运输阶段的所有成功移动。
## 先统一进入并行动画/状态，再统一完成落位，避免前一个物体先提交后影响后一个物体判定。
func _apply_transport_phase(beat_index: int, item_commands: Dictionary, move_success_by_id: Dictionary) -> void:
	var successful_moves: Array[Dictionary] = []
	for item_id in move_success_by_id.keys():
		if not bool(move_success_by_id[item_id]):
			continue

		var command: Dictionary = item_commands[item_id]
		var item: Item = command["item"] as Item
		if item == null or not is_instance_valid(item):
			continue

		item.mark_resolved_on_beat(beat_index)
		item.begin_parallel_move()
		successful_moves.append(command)

	for command in successful_moves:
		var item: Item = command["item"] as Item
		if item == null or not is_instance_valid(item):
			continue

		item.complete_parallel_move(command["target_cell"])
		item.mark_resolved_on_beat(beat_index)


## 执行出料阶段。
## 本阶段只处理机器向地图生成新物体或释放成品；若多个出料请求撞到同一格，则全部取消。
func _apply_output_phase(beat_index: int) -> void:
	var output_requests: Array = _collect_output_requests(beat_index)
	var target_counts: Dictionary = {}

	for request in output_requests:
		var target_cell: Vector2i = request["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in output_requests:
		var target_cell: Vector2i = request["target_cell"]
		if int(target_counts.get(target_cell, 0)) != 1:
			# 出料冲突不做仲裁，保持所有请求失败。
			continue

		if _world.item_layer.has_cell(target_cell):
			continue

		var output_kind: StringName = request["kind"]
		match output_kind:
			&"producer":
				var producer: Producer = request["machine"] as Producer
				if producer == null or not is_instance_valid(producer):
					continue

				var produced_item: Item = _world.spawn_item(target_cell, producer.get_pending_output_cargo_type(), Item.Kind.CARGO)
				if produced_item == null:
					continue

				produced_item.mark_resolved_on_beat(beat_index)
				producer.commit_output_success()
			&"press_machine":
				var press_machine: PressMachine = request["machine"] as PressMachine
				if press_machine == null or not is_instance_valid(press_machine):
					continue

				var released_item: Item = press_machine.release_output(target_cell)
				if released_item == null:
					continue

				released_item.mark_resolved_on_beat(beat_index)
			&"packer":
				var packer: Packer = request["machine"] as Packer
				if packer == null or not is_instance_valid(packer):
					continue

				var product: Item = _world.spawn_item(target_cell, packer.get_pending_output_item_type(), Item.Kind.PRODUCT)
				if product == null:
					continue

				product.mark_resolved_on_beat(beat_index)
				packer.commit_output_success()
			_:
				pass


## 收集本拍所有机器的出料请求，但此时不真正生成物体。
## 返回值中的 `kind` 用来在提交阶段区分不同机器的出料逻辑。
func _collect_output_requests(beat_index: int) -> Array:
	var output_requests: Array = []

	var producer_cells: Dictionary = _world.producer_layer.get_cells()
	for cell in producer_cells.keys():
		var producer: Producer = producer_cells[cell] as Producer
		if producer == null or not is_instance_valid(producer):
			continue

		if not producer.can_output_on_beat(beat_index):
			continue

		output_requests.append({
			"kind": &"producer",
			"machine": producer,
			"target_cell": producer.get_target_cell(),
		})

	var press_machine_cells: Dictionary = _world.press_machine_layer.get_cells()
	for cell in press_machine_cells.keys():
		var press_machine: PressMachine = press_machine_cells[cell] as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if not press_machine.can_output_on_beat(beat_index):
			continue

		output_requests.append({
			"kind": &"press_machine",
			"machine": press_machine,
			"target_cell": press_machine.get_target_cell(),
		})

	var packer_cells: Dictionary = _world.packer_layer.get_cells()
	for cell in packer_cells.keys():
		var packer: Packer = packer_cells[cell] as Packer
		if packer == null or not is_instance_valid(packer):
			continue

		if not packer.can_output_on_beat(beat_index):
			continue

		output_requests.append({
			"kind": &"packer",
			"machine": packer,
			"target_cell": packer.get_target_cell(),
		})

	return output_requests


## 执行输入阶段，处理拍初运输物体与当前格机器的交互。
## 这里只处理拍初已存在的运输物体，确保新出料或新变形物体不会在同拍再次入机。
## 返回值表示回收器是否在本拍收到了新的有效进度，用于胜利判定。
func _apply_input_phase(beat_index: int, beat_snapshot: Dictionary, item_ids: Dictionary) -> bool:
	var did_recycler_progress: bool = false
	var current_items: Dictionary = _world.item_layer.get_cells().duplicate()
	var triggered_press_machines: Dictionary = beat_snapshot["triggered_press_machines"]
	var triggered_packers: Dictionary = beat_snapshot["triggered_packers"]

	for cell in current_items.keys():
		var item: Item = current_items[cell] as Item
		if item == null or not is_instance_valid(item):
			continue

		if not item_ids.has(item.get_instance_id()):
			continue

		var recycler: Recycler = _world.recycler_layer.get_cell(cell) as Recycler
		if recycler != null and is_instance_valid(recycler):
			if _apply_recycler_input(item, recycler):
				# 回收成功后，本拍不再继续尝试其他输入交互。
				item.mark_resolved_on_beat(beat_index)
				if item.is_product():
					did_recycler_progress = true
				continue

		var press_machine: PressMachine = _world.press_machine_layer.get_cell(cell) as PressMachine
		if item.is_cargo() and press_machine != null and is_instance_valid(press_machine) and press_machine.can_accept_input(triggered_press_machines.has(cell)):
			press_machine.accept_input(item)
			item.mark_resolved_on_beat(beat_index)
			continue

		var packer: Packer = _world.packer_layer.get_cell(cell) as Packer
		if item.is_cargo() and packer != null and is_instance_valid(packer) and packer.can_accept_input(triggered_packers.has(cell)):
			packer.accept_input(item)
			item.mark_resolved_on_beat(beat_index)

	return did_recycler_progress


## 处理单个物体进入回收器时的结算。
## 原料会直接销毁并计入日志，成品则交由回收器判定是否满足收集条件。
func _apply_recycler_input(item: Item, recycler: Recycler) -> bool:
	if item.is_cargo():
		var item_type: String = item.item_type
		item.remove_from_world()
		recycler.log_cargo_destroyed(item_type)
		return true

	if item.is_product():
		return recycler.collect_product(item)

	return false


## 执行开始阶段，启动各机器在本拍可以开始的新生产/加工周期。
## 这个阶段放在输入之后，保证机器先吃到本拍输入，再决定是否开始工作。
func _apply_start_phase(beat_index: int, beat_snapshot: Dictionary) -> void:
	var producer_cells: Dictionary = _world.producer_layer.get_cells()
	for cell in producer_cells.keys():
		var producer: Producer = producer_cells[cell] as Producer
		if producer == null or not is_instance_valid(producer):
			continue

		if producer.can_start_cycle(beat_index):
			producer.start_cycle(beat_index)

	var triggered_press_machines: Dictionary = beat_snapshot["triggered_press_machines"]
	var press_machine_cells: Dictionary = _world.press_machine_layer.get_cells()
	for cell in press_machine_cells.keys():
		var press_machine: PressMachine = press_machine_cells[cell] as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if not press_machine.can_start_cycle(beat_index, triggered_press_machines.has(cell)):
			continue

		var pressed_item: Item = press_machine.get_pressed_item()
		if pressed_item == null or not is_instance_valid(pressed_item):
			continue

		pressed_item.item_type = press_machine.cargo_type
		press_machine.begin_press(pressed_item, beat_index)

	var triggered_packers: Dictionary = beat_snapshot["triggered_packers"]
	var packer_cells: Dictionary = _world.packer_layer.get_cells()
	for cell in packer_cells.keys():
		var packer: Packer = packer_cells[cell] as Packer
		if packer == null or not is_instance_valid(packer):
			continue

		if packer.can_start_cycle(beat_index, triggered_packers.has(cell)):
			packer.start_cycle(beat_index)

## 判断指令类型是否属于移动类指令。
func _is_move_command(command_type: StringName) -> bool:
	return command_type == ITEM_COMMAND_MOVE_TO_CELL
