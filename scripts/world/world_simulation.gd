class_name WorldSimulation
extends RefCounted

const TRIGGERED_SORTERS_KEY: StringName = &"sorters"
const TRIGGERED_PRESS_MACHINES_KEY: StringName = &"press_machines"
const TRIGGERED_PACKERS_KEY: StringName = &"packers"

const ITEM_COMMAND_WAIT: StringName = &"WAIT"
const ITEM_COMMAND_MOVE_TO_CELL: StringName = &"MOVE_TO_CELL"
const ITEM_COMMAND_PACK_IN_PLACE: StringName = &"PACK_IN_PLACE"
const ITEM_COMMAND_PRESS_IN_PLACE: StringName = &"PRESS_IN_PLACE"
const ITEM_COMMAND_RECYCLE_PRODUCT: StringName = &"RECYCLE_PRODUCT"
const ITEM_COMMAND_RECYCLE_CARGO: StringName = &"RECYCLE_CARGO"

var _world: World


func _init(world: World) -> void:
	assert(world != null, "WorldSimulation requires a World instance.")
	_world = world


# 拍点结算按“信号快照 -> 机器给脚下物体下命令 -> 提交阶段统一执行”运行。
func resolve_beat(beat_index: int, signal_snapshot: Dictionary) -> void:
	var beat_snapshot: Dictionary = _create_beat_snapshot(beat_index, signal_snapshot)
	var machine_plan: Dictionary = _create_machine_plan(beat_snapshot)
	var item_commands: Dictionary = _create_item_commands(beat_snapshot, machine_plan)
	var move_success_by_id: Dictionary = _resolve_move_successes(beat_snapshot["items"], item_commands)
	var did_recycler_progress: bool = _apply_item_commands(beat_index, item_commands, move_success_by_id)
	_apply_sorter_toggles(machine_plan)
	_apply_producer_spawns(beat_index, machine_plan)

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
		"producer_spawns": [],
	}

	_plan_sorters(beat_snapshot, machine_plan)
	_plan_producers(beat_snapshot, machine_plan)
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


func _plan_producers(beat_snapshot: Dictionary, machine_plan: Dictionary) -> void:
	var items: Dictionary = beat_snapshot["items"]
	var beat_index: int = int(beat_snapshot["beat_index"])
	var producer_cells: Dictionary = _world.producer_layer.get_cells()

	for cell in producer_cells.keys():
		var producer: Producer = producer_cells[cell] as Producer
		if producer == null or not is_instance_valid(producer):
			continue

		if not producer.should_trigger_on_beat(beat_index):
			continue

		if not producer.has_remaining_production():
			continue

		var target_cell: Vector2i = producer.get_target_cell()
		if items.has(target_cell):
			continue

		machine_plan["producer_spawns"].append({
			"producer": producer,
			"target_cell": target_cell,
			"cargo_type": producer.get_next_cargo_type(),
		})


func _create_item_commands(beat_snapshot: Dictionary, machine_plan: Dictionary) -> Dictionary:
	var item_commands: Dictionary = {}
	var items: Dictionary = beat_snapshot["items"]

	for cell in items.keys():
		var item: TransportItem = items[cell] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		item_commands[item.get_instance_id()] = _create_item_command(cell, item, beat_snapshot, machine_plan)

	return item_commands


func _create_item_command(cell: Vector2i, item: TransportItem, beat_snapshot: Dictionary, machine_plan: Dictionary) -> Dictionary:
	var press_machine: PressMachine = _world.press_machine_layer.get_cell(cell) as PressMachine
	if press_machine != null and is_instance_valid(press_machine):
		return _create_press_machine_command(cell, item, press_machine, beat_snapshot)

	var packer: Packer = _world.packer_layer.get_cell(cell) as Packer
	if packer != null and is_instance_valid(packer):
		return _create_packer_command(cell, item, packer, beat_snapshot)

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
		return _create_recycler_command(cell, item, recycler)

	return _create_wait_command(item, cell)


func _create_recycler_command(cell: Vector2i, item: TransportItem, recycler: Recycler) -> Dictionary:
	var cargo: Cargo = item as Cargo
	if cargo != null and is_instance_valid(cargo):
		return _create_command(
			ITEM_COMMAND_RECYCLE_CARGO,
			item,
			cell,
			{
				"recycler": recycler,
			}
		)

	var product: Product = item as Product
	if product != null and is_instance_valid(product) and recycler.can_accept_product(product.product_type):
		return _create_command(
			ITEM_COMMAND_RECYCLE_PRODUCT,
			item,
			cell,
			{
				"recycler": recycler,
			}
		)

	return _create_wait_command(item, cell)


func _create_press_machine_command(cell: Vector2i, item: TransportItem, press_machine: PressMachine, beat_snapshot: Dictionary) -> Dictionary:
	var cargo: Cargo = item as Cargo
	if cargo == null or not is_instance_valid(cargo):
		return _create_wait_command(item, cell)

	if press_machine.is_pressing():
		var pressed_cargo: Cargo = press_machine.get_pressed_cargo()
		if pressed_cargo != cargo:
			return _create_wait_command(item, cell)

		if not press_machine.has_finished_press(int(beat_snapshot["beat_index"])):
			return _create_wait_command(item, cell)

		return _create_move_command(
			item,
			cell,
			press_machine.get_target_cell(),
			{
				"clear_press_machine": press_machine,
			}
		)

	var triggered_press_machines: Dictionary = beat_snapshot["triggered_press_machines"]
	if triggered_press_machines.has(cell):
		return _create_command(
			ITEM_COMMAND_PRESS_IN_PLACE,
			item,
			cell,
			{
				"press_machine": press_machine,
				"result_type": press_machine.cargo_type,
			}
		)

	return _create_move_command(item, cell, press_machine.get_target_cell(), {})


func _create_packer_command(cell: Vector2i, item: TransportItem, packer: Packer, beat_snapshot: Dictionary) -> Dictionary:
	var product: Product = item as Product
	if product != null and is_instance_valid(product):
		return _create_move_command(item, cell, packer.get_target_cell(), {})

	var cargo: Cargo = item as Cargo
	if cargo == null or not is_instance_valid(cargo):
		return _create_wait_command(item, cell)

	var triggered_packers: Dictionary = beat_snapshot["triggered_packers"]
	if triggered_packers.has(cell):
		return _create_command(
			ITEM_COMMAND_PACK_IN_PLACE,
			item,
			cell,
			{
				"result_type": cargo.cargo_type,
			}
		)

	return _create_move_command(item, cell, packer.get_target_cell(), {})


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
	if occupant_command_type == ITEM_COMMAND_RECYCLE_PRODUCT or occupant_command_type == ITEM_COMMAND_RECYCLE_CARGO:
		return true

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


func _apply_item_commands(beat_index: int, item_commands: Dictionary, move_success_by_id: Dictionary) -> bool:
	var did_recycler_progress: bool = false

	for command in item_commands.values():
		var item: TransportItem = command["item"] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		item.mark_resolved_on_beat(beat_index)

	for command in item_commands.values():
		var command_type: StringName = command["type"]
		if _is_move_command(command_type):
			continue

		var item: TransportItem = command["item"] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		match command_type:
			ITEM_COMMAND_PACK_IN_PLACE:
				var cargo_to_pack: Cargo = item as Cargo
				if cargo_to_pack == null or not is_instance_valid(cargo_to_pack):
					continue

				var packed_cell: Vector2i = command["from_cell"]
				var product_type: String = String(command["result_type"])
				cargo_to_pack.remove_from_world()
				var product: Product = _world.spawn_product(packed_cell, product_type)
				if product != null:
					product.mark_resolved_on_beat(beat_index)
			ITEM_COMMAND_PRESS_IN_PLACE:
				var cargo_to_press: Cargo = item as Cargo
				var press_machine: PressMachine = command["press_machine"] as PressMachine
				if cargo_to_press == null or not is_instance_valid(cargo_to_press):
					continue

				cargo_to_press.cargo_type = String(command["result_type"])
				if press_machine != null and is_instance_valid(press_machine) and not press_machine.is_pressing():
					press_machine.begin_press(cargo_to_press, beat_index)
			ITEM_COMMAND_RECYCLE_CARGO:
				var recycler_for_cargo: Recycler = command["recycler"] as Recycler
				var cargo_to_destroy: Cargo = item as Cargo
				if recycler_for_cargo != null and is_instance_valid(recycler_for_cargo) and cargo_to_destroy != null and is_instance_valid(cargo_to_destroy):
					var cargo_type: String = cargo_to_destroy.cargo_type
					cargo_to_destroy.remove_from_world()
					recycler_for_cargo.log_cargo_destroyed(cargo_type)
			ITEM_COMMAND_RECYCLE_PRODUCT:
				var recycler_for_product: Recycler = command["recycler"] as Recycler
				var product_to_collect: Product = item as Product
				if recycler_for_product != null and is_instance_valid(recycler_for_product) and product_to_collect != null and is_instance_valid(product_to_collect):
					if recycler_for_product.collect_product(product_to_collect):
						did_recycler_progress = true
			_:
				pass

	var successful_moves: Array[Dictionary] = []
	for item_id in move_success_by_id.keys():
		if not bool(move_success_by_id[item_id]):
			continue

		var command: Dictionary = item_commands[item_id]
		var item: TransportItem = command["item"] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		item.begin_parallel_move()
		successful_moves.append(command)

	for command in successful_moves:
		var item: TransportItem = command["item"] as TransportItem
		if item == null or not is_instance_valid(item):
			continue

		item.complete_parallel_move(command["target_cell"])

		var clear_press_machine: PressMachine = command.get("clear_press_machine") as PressMachine
		if clear_press_machine != null and is_instance_valid(clear_press_machine):
			clear_press_machine.clear_pressed_cargo()

	return did_recycler_progress


func _apply_sorter_toggles(machine_plan: Dictionary) -> void:
	var sorter_toggle_cells: Dictionary = machine_plan["sorter_toggle_cells"]
	for cell in sorter_toggle_cells.keys():
		var sorter: Sorter = sorter_toggle_cells[cell] as Sorter
		if sorter == null or not is_instance_valid(sorter):
			continue

		sorter.toggle_output()


func _apply_producer_spawns(beat_index: int, machine_plan: Dictionary) -> void:
	var producer_spawns: Array = machine_plan["producer_spawns"]
	var target_counts: Dictionary = {}

	for spawn_request in producer_spawns:
		var target_cell: Vector2i = spawn_request["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for spawn_request in producer_spawns:
		var producer: Producer = spawn_request["producer"] as Producer
		if producer == null or not is_instance_valid(producer):
			continue

		var target_cell: Vector2i = spawn_request["target_cell"]
		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if _world.item_layer.has_cell(target_cell):
			continue

		var cargo: Cargo = _world.spawn_cargo(target_cell, String(spawn_request["cargo_type"]))
		if cargo == null:
			continue

		cargo.mark_resolved_on_beat(beat_index)
		producer.mark_produced()


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
