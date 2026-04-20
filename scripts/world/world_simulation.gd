class_name WorldSimulation
extends RefCounted

const TRIGGERED_SORTERS_KEY: StringName = &"sorters"
const TRIGGERED_PRESS_MACHINES_KEY: StringName = &"press_machines"
const TRIGGERED_PACKERS_KEY: StringName = &"packers"

const ITEM_COMMAND_WAIT: StringName = &"WAIT"
const ITEM_COMMAND_MOVE_TO_CELL: StringName = &"MOVE_TO_CELL"

var _world: World


func _init(world: World) -> void:
	assert(world != null, "WorldSimulation requires a World instance.")
	_world = world


# 拍点结算按“信号快照 -> Output -> Transport -> Input -> Start -> Commit”运行。
func resolve_beat(beat_index: int, signal_snapshot: Dictionary) -> void:
	var beat_snapshot: Dictionary = _create_beat_snapshot(beat_index, signal_snapshot)
	var machine_plan: Dictionary = _create_machine_plan(beat_snapshot)
	var transport_item_ids: Dictionary = _collect_transport_item_ids(beat_snapshot["items"])
	_apply_output_phase(beat_index)
	var transport_commands: Dictionary = _create_transport_commands(beat_snapshot, machine_plan)
	var transport_snapshot_items: Dictionary = _world.item_layer.get_cells().duplicate()
	var move_success_by_id: Dictionary = _resolve_move_successes(transport_snapshot_items, transport_commands)
	_apply_transport_phase(beat_index, transport_commands, move_success_by_id)
	var did_recycler_progress: bool = _apply_input_phase(beat_index, beat_snapshot, transport_item_ids)
	_apply_start_phase(beat_index, beat_snapshot)
	_apply_sorter_toggles(machine_plan)

	if did_recycler_progress and _world.are_all_recyclers_completed():
		GM.finish_game(true)


func _create_beat_snapshot(beat_index: int, signal_snapshot: Dictionary) -> Dictionary:
	return {
		"beat_index": beat_index,
		"items": _world.item_layer.get_cells().duplicate(),
		"triggered_sorters": signal_snapshot.get(TRIGGERED_SORTERS_KEY, {}),
		"triggered_press_machines": signal_snapshot.get(TRIGGERED_PRESS_MACHINES_KEY, {}),
		"triggered_packers": signal_snapshot.get(TRIGGERED_PACKERS_KEY, {}),
	}


func _create_machine_plan(beat_snapshot: Dictionary) -> Dictionary:
	var machine_plan: Dictionary = {
		"sorter_toggle_cells": {},
		"sorter_target_cells": {},
	}

	_plan_sorters(beat_snapshot, machine_plan)
	return machine_plan


func _plan_sorters(beat_snapshot: Dictionary, machine_plan: Dictionary) -> void:
	var triggered_sorters: Dictionary = beat_snapshot["triggered_sorters"]
	var sorter_cells: Dictionary = _world.sorter_layer.get_cells()

	for cell in sorter_cells.keys():
		var sorter: Sorter = sorter_cells[cell] as Sorter
		if sorter == null or not is_instance_valid(sorter):
			continue

		var should_toggle: bool = triggered_sorters.has(cell)
		if should_toggle:
			machine_plan["sorter_toggle_cells"][cell] = sorter

		machine_plan["sorter_target_cells"][cell] = _get_sorter_target_cell(sorter, should_toggle)


func _collect_transport_item_ids(items: Dictionary) -> Dictionary:
	var transport_item_ids: Dictionary = {}
	for item in items.values():
		var transport_item: TransportItem = item as TransportItem
		if transport_item == null or not is_instance_valid(transport_item):
			continue

		transport_item_ids[transport_item.get_instance_id()] = true

	return transport_item_ids


func _create_transport_commands(beat_snapshot: Dictionary, machine_plan: Dictionary) -> Dictionary:
	var item_commands: Dictionary = {}
	var items: Dictionary = beat_snapshot["items"]

	for cell in items.keys():
		var item: TransportItem = items[cell] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		item_commands[item.get_instance_id()] = _create_transport_command(cell, item, beat_snapshot, machine_plan)

	return item_commands


func _create_transport_command(cell: Vector2i, item: TransportItem, beat_snapshot: Dictionary, machine_plan: Dictionary) -> Dictionary:
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

	var sorter: Sorter = _world.sorter_layer.get_cell(cell) as Sorter
	if sorter != null and is_instance_valid(sorter) and sorter.should_trigger_on_beat(beat_index):
		var sorter_target_cell: Vector2i = machine_plan["sorter_target_cells"].get(cell, sorter.get_target_cell())
		return _create_move_command(item, cell, sorter_target_cell, {})

	var recycler: Recycler = _world.recycler_layer.get_cell(cell) as Recycler
	if recycler != null and is_instance_valid(recycler):
		return _create_wait_command(item, cell)

	return _create_wait_command(item, cell)


func _create_wait_command(item: TransportItem, from_cell: Vector2i) -> Dictionary:
	return _create_command(ITEM_COMMAND_WAIT, item, from_cell, {})


func _create_move_command(item: TransportItem, from_cell: Vector2i, target_cell: Vector2i, extra_data: Dictionary) -> Dictionary:
	var command: Dictionary = _create_command(ITEM_COMMAND_MOVE_TO_CELL, item, from_cell, extra_data)
	command["target_cell"] = target_cell
	return command


func _create_command(command_type: StringName, item: TransportItem, from_cell: Vector2i, extra_data: Dictionary) -> Dictionary:
	var command: Dictionary = {
		"type": command_type,
		"item": item,
		"from_cell": from_cell,
	}

	for key in extra_data.keys():
		command[key] = extra_data[key]

	return command


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


func _resolve_move_success(item_id: int, snapshot_items: Dictionary, item_commands: Dictionary, target_to_item_ids: Dictionary, resolve_states: Dictionary, move_success_by_id: Dictionary) -> bool:
	if move_success_by_id.has(item_id):
		return bool(move_success_by_id[item_id])

	var resolve_state: int = int(resolve_states.get(item_id, 0))
	if resolve_state == 1:
		return false

	resolve_states[item_id] = 1

	var command: Dictionary = item_commands[item_id]
	var target_cell: Vector2i = command["target_cell"]
	var incoming_item_ids: Array = target_to_item_ids.get(target_cell, [])
	if incoming_item_ids.size() != 1:
		move_success_by_id[item_id] = false
		resolve_states[item_id] = 2
		return false

	var target_occupant: TransportItem = snapshot_items.get(target_cell) as TransportItem
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


func _will_cell_be_released(cell: Vector2i, snapshot_items: Dictionary, item_commands: Dictionary, target_to_item_ids: Dictionary, resolve_states: Dictionary, move_success_by_id: Dictionary) -> bool:
	var occupant: TransportItem = snapshot_items.get(cell) as TransportItem
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


func _apply_transport_phase(beat_index: int, item_commands: Dictionary, move_success_by_id: Dictionary) -> void:
	var successful_moves: Array[Dictionary] = []
	for item_id in move_success_by_id.keys():
		if not bool(move_success_by_id[item_id]):
			continue

		var command: Dictionary = item_commands[item_id]
		var item: TransportItem = command["item"] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		item.mark_resolved_on_beat(beat_index)
		item.begin_parallel_move()
		successful_moves.append(command)

	for command in successful_moves:
		var item: TransportItem = command["item"] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		item.complete_parallel_move(command["target_cell"])
		item.mark_resolved_on_beat(beat_index)


func _apply_sorter_toggles(machine_plan: Dictionary) -> void:
	var sorter_toggle_cells: Dictionary = machine_plan["sorter_toggle_cells"]
	for cell in sorter_toggle_cells.keys():
		var sorter: Sorter = sorter_toggle_cells[cell] as Sorter
		if sorter == null or not is_instance_valid(sorter):
			continue

		sorter.toggle_output()


func _apply_output_phase(beat_index: int) -> void:
	var output_requests: Array = _collect_output_requests(beat_index)
	var target_counts: Dictionary = {}

	for request in output_requests:
		var target_cell: Vector2i = request["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in output_requests:
		var target_cell: Vector2i = request["target_cell"]
		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if _world.item_layer.has_cell(target_cell):
			continue

		var output_kind: StringName = request["kind"]
		match output_kind:
			&"producer":
				var producer: Producer = request["machine"] as Producer
				if producer == null or not is_instance_valid(producer):
					continue

				var produced_cargo: Cargo = _world.spawn_cargo(target_cell, producer.get_pending_output_cargo_type())
				if produced_cargo == null:
					continue

				produced_cargo.mark_resolved_on_beat(beat_index)
				producer.commit_output_success()
			&"press_machine":
				var press_machine: PressMachine = request["machine"] as PressMachine
				if press_machine == null or not is_instance_valid(press_machine):
					continue

				var released_cargo: Cargo = press_machine.release_output(target_cell)
				if released_cargo == null:
					continue

				released_cargo.mark_resolved_on_beat(beat_index)
			&"packer":
				var packer: Packer = request["machine"] as Packer
				if packer == null or not is_instance_valid(packer):
					continue

				var product: Product = _world.spawn_product(target_cell, packer.get_pending_output_product_type())
				if product == null:
					continue

				product.mark_resolved_on_beat(beat_index)
				packer.commit_output_success()
			_:
				pass


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


func _apply_input_phase(beat_index: int, beat_snapshot: Dictionary, transport_item_ids: Dictionary) -> bool:
	var did_recycler_progress: bool = false
	var current_items: Dictionary = _world.item_layer.get_cells().duplicate()
	var triggered_press_machines: Dictionary = beat_snapshot["triggered_press_machines"]
	var triggered_packers: Dictionary = beat_snapshot["triggered_packers"]

	for cell in current_items.keys():
		var item: TransportItem = current_items[cell] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		if not transport_item_ids.has(item.get_instance_id()):
			continue

		var recycler: Recycler = _world.recycler_layer.get_cell(cell) as Recycler
		if recycler != null and is_instance_valid(recycler):
			if _apply_recycler_input(item, recycler):
				item.mark_resolved_on_beat(beat_index)
				if item is Product:
					did_recycler_progress = true
				continue

		var cargo: Cargo = item as Cargo
		var press_machine: PressMachine = _world.press_machine_layer.get_cell(cell) as PressMachine
		if cargo != null and is_instance_valid(cargo) and press_machine != null and is_instance_valid(press_machine) and press_machine.can_accept_input(triggered_press_machines.has(cell)):
			press_machine.accept_input(cargo)
			cargo.mark_resolved_on_beat(beat_index)
			continue

		var packer: Packer = _world.packer_layer.get_cell(cell) as Packer
		if cargo != null and is_instance_valid(cargo) and packer != null and is_instance_valid(packer) and packer.can_accept_input(triggered_packers.has(cell)):
			packer.accept_input(cargo)
			cargo.mark_resolved_on_beat(beat_index)

	return did_recycler_progress


func _apply_recycler_input(item: TransportItem, recycler: Recycler) -> bool:
	var cargo: Cargo = item as Cargo
	if cargo != null and is_instance_valid(cargo):
		var cargo_type: String = cargo.cargo_type
		cargo.remove_from_world()
		recycler.log_cargo_destroyed(cargo_type)
		return true

	var product: Product = item as Product
	if product != null and is_instance_valid(product):
		return recycler.collect_product(product)

	return false


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

		var pressed_cargo: Cargo = press_machine.get_pressed_cargo()
		if pressed_cargo == null or not is_instance_valid(pressed_cargo):
			continue

		pressed_cargo.cargo_type = press_machine.cargo_type
		press_machine.begin_press(pressed_cargo, beat_index)

	var triggered_packers: Dictionary = beat_snapshot["triggered_packers"]
	var packer_cells: Dictionary = _world.packer_layer.get_cells()
	for cell in packer_cells.keys():
		var packer: Packer = packer_cells[cell] as Packer
		if packer == null or not is_instance_valid(packer):
			continue

		if packer.can_start_cycle(beat_index, triggered_packers.has(cell)):
			packer.start_cycle(beat_index)


func _get_sorter_target_cell(sorter: Sorter, should_toggle: bool) -> Vector2i:
	var current_target_cell: Vector2i = sorter.get_target_cell()
	if not should_toggle:
		return current_target_cell

	var sorter_cell: Vector2i = sorter.get_registered_cell()
	var left_target_cell: Vector2i = sorter_cell + _sorter_direction_to_offset(_rotate_sorter_left(sorter.input_direction))
	var right_target_cell: Vector2i = sorter_cell + _sorter_direction_to_offset(_rotate_sorter_right(sorter.input_direction))
	if current_target_cell == left_target_cell:
		return right_target_cell

	return left_target_cell


func _rotate_sorter_left(direction: Sorter.InputDirection) -> Sorter.InputDirection:
	return wrapi(int(direction) - 1, 0, 4) as Sorter.InputDirection


func _rotate_sorter_right(direction: Sorter.InputDirection) -> Sorter.InputDirection:
	return wrapi(int(direction) + 1, 0, 4) as Sorter.InputDirection


func _sorter_direction_to_offset(direction: Sorter.InputDirection) -> Vector2i:
	match direction:
		Sorter.InputDirection.UP:
			return Vector2i.UP
		Sorter.InputDirection.RIGHT:
			return Vector2i.RIGHT
		Sorter.InputDirection.DOWN:
			return Vector2i.DOWN
		_:
			return Vector2i.LEFT


func _is_move_command(command_type: StringName) -> bool:
	return command_type == ITEM_COMMAND_MOVE_TO_CELL
