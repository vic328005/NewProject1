## 负责单个拍点内的世界结算。
class_name WorldSimulation
extends RefCounted

const OUTPUT_ACTION_NONE: String = "none"
const OUTPUT_ACTION_SPAWN: String = "spawn"
const OUTPUT_ACTION_RELEASE: String = "release"
const INPUT_ACTION_REJECT: String = "reject"
const INPUT_ACTION_ACCEPT: String = "accept"
const INPUT_ACTION_DESTROY: String = "destroy"
const TRANSPORT_ACTION_BLOCK: String = "block"
const TRANSPORT_ACTION_MOVE: String = "move"
const ITEM_RESULT_STAY: String = "stay"
const ITEM_RESULT_MOVE: String = "move"

var _world: World


## 绑定要结算的世界实例。
func _init(world: World) -> void:
	assert(world != null, "WorldSimulation requires a World instance.")
	_world = world


## 执行一次完整拍点结算。
func resolve_beat(beat_index: int) -> void:
	var machines: Array[Machine] = _collect_machines()
	var machine_signal_states: Dictionary = _collect_machine_signal_states(machines)
	var item_snapshot: Dictionary = _collect_item_snapshot()
	var input_results: Dictionary = _plan_inputs(item_snapshot, machine_signal_states, beat_index)

	_commit_inputs(input_results, beat_index)
	_update_machine_states(machines, machine_signal_states, beat_index)

	var output_item_snapshot: Dictionary = _collect_item_snapshot()
	var output_results: Array[Dictionary] = _plan_outputs(machines, machine_signal_states, output_item_snapshot, beat_index)
	var output_reserved_cells: Dictionary = _collect_output_reserved_cells(output_results)
	_commit_outputs(output_results, beat_index)

	var transport_results: Dictionary = _plan_transports(item_snapshot, machine_signal_states, output_reserved_cells, input_results, beat_index)
	_commit_moves(transport_results, beat_index)
	_mark_remaining_items_resolved(item_snapshot, transport_results, input_results, beat_index)
	_update_signal_waves(beat_index)
	if _world.are_all_recyclers_completed():
		GM.finish_game(true)


func _update_signal_waves(beat_index: int) -> void:
	# 当前先实现信号阶段：在一次遍历里推进并清理信号波。
	for node in _world.get_tree().get_nodes_in_group(SignalWave.GROUP_NAME):
		var signal_wave: SignalWave = node as SignalWave
		if signal_wave == null:
			continue

		if signal_wave.is_finished():
			signal_wave.remove_from_world()
			continue

		signal_wave.advance(beat_index)
		if signal_wave.is_finished():
			signal_wave.remove_from_world()


func _collect_machines() -> Array[Machine]:
	var machines: Array[Machine] = []
	var machine_cells: Dictionary = _world.machine_layer.get_cells()
	for cell in machine_cells.keys():
		var machine: Machine = machine_cells[cell] as Machine
		if machine == null or not is_instance_valid(machine):
			continue

		machines.append(machine)

	return machines


func _collect_item_snapshot() -> Dictionary:
	var item_snapshot: Dictionary = {}
	var item_cells: Dictionary = _world.item_layer.get_cells()
	for cell in item_cells.keys():
		var item: Item = item_cells[cell] as Item
		if item == null or not is_instance_valid(item):
			continue

		item_snapshot[cell] = item

	return item_snapshot


func _collect_machine_signal_states(machines: Array[Machine]) -> Dictionary:
	var machine_signal_states: Dictionary = {}
	for machine in machines:
		machine_signal_states[machine] = _world.signal_layer.has_cell(machine.get_registered_cell())

	return machine_signal_states


func _plan_outputs(machines: Array[Machine], machine_signal_states: Dictionary, item_snapshot: Dictionary, beat_index: int) -> Array[Dictionary]:
	var candidate_results: Array[Dictionary] = []
	var target_counts: Dictionary = {}
	for machine in machines:
		var receives_signal: bool = bool(machine_signal_states.get(machine, false))
		var plan: Dictionary = machine.plan_output(beat_index, receives_signal)
		var action: String = String(plan.get("action", OUTPUT_ACTION_NONE))
		assert(
			action == OUTPUT_ACTION_NONE or action == OUTPUT_ACTION_SPAWN or action == OUTPUT_ACTION_RELEASE,
			"Unsupported machine output action: %s" % action
		)

		if action == OUTPUT_ACTION_NONE:
			continue

		assert(plan.has("target_cell"), "Output plan must contain target_cell.")
		var target_cell: Vector2i = plan["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1
		candidate_results.append({
			"machine": machine,
			"plan": plan,
		})

	var output_results: Array[Dictionary] = []
	for output_result in candidate_results:
		var plan: Dictionary = output_result["plan"]
		var target_cell: Vector2i = plan["target_cell"]
		if int(target_counts[target_cell]) > 1:
			continue

		if item_snapshot.has(target_cell):
			continue

		output_results.append(output_result)

	return output_results


func _collect_output_reserved_cells(output_results: Array[Dictionary]) -> Dictionary:
	var reserved_cells: Dictionary = {}
	for output_result in output_results:
		var plan: Dictionary = output_result["plan"]
		var target_cell: Vector2i = plan["target_cell"]
		reserved_cells[target_cell] = true

	return reserved_cells


func _plan_transports(item_snapshot: Dictionary, machine_signal_states: Dictionary, output_reserved_cells: Dictionary, input_results: Dictionary, beat_index: int) -> Dictionary:
	var transport_results: Dictionary = {}
	for cell in item_snapshot.keys():
		var item: Item = item_snapshot[cell] as Item
		if item == null or not is_instance_valid(item):
			continue

		if input_results.has(item):
			continue

		var result: Dictionary = {
			"action": ITEM_RESULT_STAY,
		}
		var machine: Machine = _world.get_machine(cell)
		if machine == null or not is_instance_valid(machine):
			transport_results[item] = result
			continue

		var receives_signal: bool = bool(machine_signal_states.get(machine, false))
		var plan: Dictionary = machine.plan_transport(item, beat_index, receives_signal)
		var action: String = String(plan.get("action", TRANSPORT_ACTION_BLOCK))
		assert(
			action == TRANSPORT_ACTION_BLOCK or action == TRANSPORT_ACTION_MOVE,
			"Unsupported machine transport action: %s" % action
		)

		if action == TRANSPORT_ACTION_MOVE:
			assert(plan.has("target_cell"), "Transport plan must contain target_cell.")
			var target_cell: Vector2i = plan["target_cell"]
			if not output_reserved_cells.has(target_cell):
				result["action"] = ITEM_RESULT_MOVE
				result["target_cell"] = target_cell
				result["flow_direction"] = plan["flow_direction"]

		transport_results[item] = result

	_resolve_parallel_move_results(item_snapshot, transport_results)
	return transport_results


func _plan_inputs(item_snapshot: Dictionary, machine_signal_states: Dictionary, beat_index: int) -> Dictionary:
	var input_results: Dictionary = {}
	for cell in item_snapshot.keys():
		var item: Item = item_snapshot[cell] as Item
		if item == null or not is_instance_valid(item):
			continue

		var machine: Machine = _world.get_machine(cell)
		if machine == null or not is_instance_valid(machine):
			continue

		var receives_signal: bool = bool(machine_signal_states.get(machine, false))
		var plan: Dictionary = machine.plan_input(item, beat_index, receives_signal)
		var action: String = String(plan.get("action", INPUT_ACTION_REJECT))
		assert(
			action == INPUT_ACTION_REJECT or action == INPUT_ACTION_ACCEPT or action == INPUT_ACTION_DESTROY,
			"Unsupported machine input action: %s" % action
		)

		if action == INPUT_ACTION_REJECT:
			continue

		input_results[item] = {
			"machine": machine,
			"plan": plan,
		}

	return input_results


func _update_machine_states(machines: Array[Machine], machine_signal_states: Dictionary, beat_index: int) -> void:
	for machine in machines:
		var receives_signal: bool = bool(machine_signal_states.get(machine, false))
		if machine is Producer:
			var producer: Producer = machine as Producer
			if not producer.should_trigger_on_beat(beat_index):
				continue

			if not producer.has_remaining_production():
				continue

			if producer._pending_output_cargo_type != "":
				continue

			producer._pending_output_cargo_type = producer.get_next_cargo_type()
			producer._output_ready_beat = beat_index + 1
			producer.mark_produced()
			continue

		if machine is Packer:
			var packer: Packer = machine as Packer
			if not packer._is_triggered_on_beat(beat_index, receives_signal):
				continue

			if not packer._is_working():
				continue

			if not packer._has_valid_held_item():
				continue

			if packer._pending_output_item_type != "":
				continue

			var output_item_type: String = packer._held_item.item_type
			if packer._held_item != null and is_instance_valid(packer._held_item):
				packer._held_item.remove_from_world()

			packer._held_item = null
			packer._pending_output_item_type = output_item_type
			packer._output_ready_beat = beat_index + 1
			packer._update_animation()
			_play_sfx(AudioController.SFX_PACKER_PACK)
			continue

		if machine is PressMachine:
			var press_machine: PressMachine = machine as PressMachine
			if not press_machine._is_triggered_on_beat(beat_index, receives_signal):
				continue

			if not press_machine._has_valid_pressed_item():
				continue

			if press_machine._output_ready_beat >= 0:
				continue

			if press_machine._pressed_item != null and is_instance_valid(press_machine._pressed_item):
				press_machine._pressed_item.item_type = press_machine.cargo_type

			press_machine._press_start_beat = beat_index
			press_machine._output_ready_beat = beat_index + 1
			_play_sfx(AudioController.SFX_PRESS_MACHINE_COMPRESS)


func _resolve_parallel_move_results(item_snapshot: Dictionary, transport_results: Dictionary) -> void:
	var target_counts: Dictionary = {}
	var valid_move_items: Dictionary = {}
	for item in transport_results.keys():
		var result: Dictionary = transport_results[item]
		if String(result["action"]) != ITEM_RESULT_MOVE:
			continue

		var target_cell: Vector2i = result["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1
		valid_move_items[item] = true

	for item in valid_move_items.keys():
		var result: Dictionary = transport_results[item]
		var target_cell: Vector2i = result["target_cell"]
		if int(target_counts[target_cell]) > 1:
			valid_move_items[item] = false

	var changed: bool = true
	while changed:
		changed = false
		for item in valid_move_items.keys():
			if not bool(valid_move_items[item]):
				continue

			var result: Dictionary = transport_results[item]
			var target_cell: Vector2i = result["target_cell"]
			var target_item: Item = item_snapshot.get(target_cell) as Item
			if target_item == null or not is_instance_valid(target_item) or target_item == item:
				continue

			if _is_item_vacating(target_item, transport_results, valid_move_items):
				continue

			valid_move_items[item] = false
			changed = true

	for item in transport_results.keys():
		var result: Dictionary = transport_results[item]
		if String(result["action"]) != ITEM_RESULT_MOVE:
			continue

		if bool(valid_move_items.get(item, false)):
			continue

		result["action"] = ITEM_RESULT_STAY
		result.erase("target_cell")
		result.erase("flow_direction")
		transport_results[item] = result


func _is_item_vacating(item: Item, transport_results: Dictionary, valid_move_items: Dictionary) -> bool:
	var result: Dictionary = transport_results.get(item, {})
	if String(result.get("action", ITEM_RESULT_STAY)) != ITEM_RESULT_MOVE:
		return false

	return bool(valid_move_items.get(item, false))


func _commit_outputs(output_results: Array[Dictionary], beat_index: int) -> void:
	for output_result in output_results:
		var machine: Machine = output_result["machine"] as Machine
		if machine == null or not is_instance_valid(machine):
			continue

		var plan: Dictionary = output_result["plan"]
		var action: String = String(plan["action"])
		if action == OUTPUT_ACTION_SPAWN:
			var spawned_item: Item = _world.spawn_item(
				plan["target_cell"],
				String(plan["item_type"]),
				plan["item_kind"],
				plan["flow_direction"]
			)
			if spawned_item == null:
				continue

			spawned_item.mark_resolved_on_beat(beat_index)
			if machine is Producer:
				_play_sfx(AudioController.SFX_PRODUCER_COUNTDOWN)
				_play_sfx(AudioController.SFX_PRODUCER_DROP)
			_apply_output_plan(machine, plan, beat_index)
			continue

		if action == OUTPUT_ACTION_RELEASE:
			var released_item: Item = plan["item"] as Item
			if released_item == null or not is_instance_valid(released_item):
				continue

			if not released_item.deploy_from_machine(plan["target_cell"], plan["flow_direction"]):
				continue

			released_item.mark_resolved_on_beat(beat_index)
			_apply_output_plan(machine, plan, beat_index)


func _commit_moves(transport_results: Dictionary, beat_index: int) -> void:
	var successful_moves: Array[Dictionary] = []
	for item in transport_results.keys():
		var result: Dictionary = transport_results[item]
		if String(result["action"]) != ITEM_RESULT_MOVE:
			continue

		successful_moves.append({
			"item": item,
			"target_cell": result["target_cell"],
			"flow_direction": result["flow_direction"],
		})

	for move_result in successful_moves:
		var item: Item = move_result["item"] as Item
		if item == null or not is_instance_valid(item):
			continue

		item.begin_parallel_move()

	for move_result in successful_moves:
		var item: Item = move_result["item"] as Item
		if item == null or not is_instance_valid(item):
			continue

		item.complete_parallel_move(move_result["target_cell"], move_result["flow_direction"])
		item.mark_resolved_on_beat(beat_index)


func _commit_inputs(input_results: Dictionary, beat_index: int) -> void:
	for item in input_results.keys():
		var input_result: Dictionary = input_results[item]
		var machine: Machine = input_result["machine"] as Machine
		if machine == null or not is_instance_valid(machine):
			continue

		var plan: Dictionary = input_result["plan"]
		var action: String = String(plan["action"])
		if action == INPUT_ACTION_ACCEPT:
			if item == null or not is_instance_valid(item):
				continue

			item.store_in_machine(machine.global_position)
			_apply_input_plan(machine, plan, item, beat_index)
			if is_instance_valid(item):
				item.mark_resolved_on_beat(beat_index)
			continue

		if action == INPUT_ACTION_DESTROY:
			if item == null or not is_instance_valid(item):
				continue

			_apply_input_plan(machine, plan, item, beat_index)
			if machine is Recycler:
				_play_sfx(AudioController.SFX_RECYCLER_DESTROY)
			if is_instance_valid(item):
				item.mark_resolved_on_beat(beat_index)
				item.remove_from_world()


func _mark_remaining_items_resolved(item_snapshot: Dictionary, transport_results: Dictionary, input_results: Dictionary, beat_index: int) -> void:
	for cell in item_snapshot.keys():
		var item: Item = item_snapshot[cell] as Item
		if item == null or not is_instance_valid(item):
			continue

		if input_results.has(item):
			continue

		var transport_result: Dictionary = transport_results.get(item, {
			"action": ITEM_RESULT_STAY,
		})
		if String(transport_result.get("action", ITEM_RESULT_STAY)) == ITEM_RESULT_MOVE:
			continue

		item.mark_resolved_on_beat(beat_index)


func _apply_output_plan(machine: Machine, _plan: Dictionary, _beat_index: int) -> void:
	if machine is Producer:
		var producer: Producer = machine as Producer
		producer._pending_output_cargo_type = ""
		producer._output_ready_beat = -1
		return

	if machine is Packer:
		var packer: Packer = machine as Packer
		packer._held_item = null
		packer._pending_output_item_type = ""
		packer._output_ready_beat = -1
		packer._enter_idle_state()
		return

	if machine is PressMachine:
		var press_machine: PressMachine = machine as PressMachine
		press_machine.clear_pressed_item()


func _apply_input_plan(machine: Machine, plan: Dictionary, item: Item, _beat_index: int) -> void:
	if machine is Packer:
		var packer: Packer = machine as Packer
		if String(plan.get("action", INPUT_ACTION_REJECT)) != INPUT_ACTION_ACCEPT:
			return

		packer._held_item = item
		packer._enter_work_state()
		return

	if machine is PressMachine:
		var press_machine: PressMachine = machine as PressMachine
		# 只有 accept 才把原料存入压塑机；destroy 时机器状态不变。
		if String(plan.get("action", INPUT_ACTION_REJECT)) != INPUT_ACTION_ACCEPT:
			return

		press_machine._enter_work_state(item)
		return

	if machine is Recycler:
		var recycler: Recycler = machine as Recycler
		if bool(plan.get("counts_as_goal", false)):
			recycler.collect_product(String(plan["product_type"]))
			return

		if plan.has("cargo_type"):
			recycler.log_cargo_destroyed(String(plan["cargo_type"]))


func _play_sfx(key: StringName) -> void:
	var audio: AudioController = GM.audio
	if not is_instance_valid(audio):
		return

	audio.play_sfx(key)
