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
const ITEM_RESULT_ACCEPT: String = "accept"
const ITEM_RESULT_DESTROY: String = "destroy"

var _world: World


## 绑定要结算的世界实例。
func _init(world: World) -> void:
	assert(world != null, "WorldSimulation requires a World instance.")
	_world = world


## 执行一次完整拍点结算。
func resolve_beat(beat_index: int) -> void:
	_update_signal_waves(beat_index)

	var machines: Array[Machine] = _collect_machines()
	_start_machines(machines, beat_index)
	var output_intents: Array[Dictionary] = _collect_output_intents(machines, beat_index)

	var item_snapshot: Dictionary = _collect_item_snapshot()
	var item_results: Dictionary = _resolve_items(item_snapshot, beat_index)
	_commit_items(item_results, beat_index)
	_commit_outputs(output_intents, beat_index)


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


func _start_machines(machines: Array[Machine], beat_index: int) -> void:
	for machine in machines:
		machine.start(beat_index)


func _collect_output_intents(machines: Array[Machine], beat_index: int) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	for machine in machines:
		var output_intent: Dictionary = machine.output(beat_index)
		var action: String = String(output_intent.get("action", OUTPUT_ACTION_NONE))
		assert(
			action == OUTPUT_ACTION_NONE or action == OUTPUT_ACTION_SPAWN or action == OUTPUT_ACTION_RELEASE,
			"Unsupported machine output action: %s" % action
		)

		if action == OUTPUT_ACTION_NONE:
			continue

		intents.append(output_intent)

	return intents


func _collect_item_snapshot() -> Dictionary:
	var item_snapshot: Dictionary = {}
	var item_cells: Dictionary = _world.item_layer.get_cells()
	for cell in item_cells.keys():
		var item: Item = item_cells[cell] as Item
		if item == null or not is_instance_valid(item):
			continue

		item_snapshot[cell] = item

	return item_snapshot


func _resolve_items(item_snapshot: Dictionary, beat_index: int) -> Dictionary:
	var item_results: Dictionary = {}
	for cell in item_snapshot.keys():
		var item: Item = item_snapshot[cell] as Item
		if item == null or not is_instance_valid(item):
			continue

		var result: Dictionary = {
			"action": ITEM_RESULT_STAY,
			"cell": cell,
		}
		var machine: Machine = _world.get_machine(cell)
		if machine == null or not is_instance_valid(machine):
			item_results[item] = result
			continue

		var input_action: String = machine.input(item, beat_index)
		assert(
			input_action == INPUT_ACTION_REJECT or input_action == INPUT_ACTION_ACCEPT or input_action == INPUT_ACTION_DESTROY,
			"Unsupported machine input action: %s" % input_action
		)

		if input_action == INPUT_ACTION_ACCEPT:
			item.mark_resolved_on_beat(beat_index)
			result["action"] = ITEM_RESULT_ACCEPT
			item_results[item] = result
			continue

		if input_action == INPUT_ACTION_DESTROY:
			if is_instance_valid(item):
				item.mark_resolved_on_beat(beat_index)

			result["action"] = ITEM_RESULT_DESTROY
			item_results[item] = result
			continue

		var transport_result: Dictionary = machine.transport(item, beat_index)
		var transport_action: String = String(transport_result.get("action", TRANSPORT_ACTION_BLOCK))
		assert(
			transport_action == TRANSPORT_ACTION_BLOCK or transport_action == TRANSPORT_ACTION_MOVE,
			"Unsupported machine transport action: %s" % transport_action
		)

		if transport_action == TRANSPORT_ACTION_MOVE:
			result["action"] = ITEM_RESULT_MOVE
			result["target_cell"] = transport_result["target_cell"]
			result["flow_direction"] = transport_result["flow_direction"]

		item_results[item] = result

	_resolve_parallel_move_results(item_snapshot, item_results)
	return item_results


func _resolve_parallel_move_results(item_snapshot: Dictionary, item_results: Dictionary) -> void:
	var target_counts: Dictionary = {}
	var valid_move_items: Dictionary = {}
	for item in item_results.keys():
		var result: Dictionary = item_results[item]
		if String(result["action"]) != ITEM_RESULT_MOVE:
			continue

		var target_cell: Vector2i = result["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1
		valid_move_items[item] = true

	for item in valid_move_items.keys():
		var result: Dictionary = item_results[item]
		var target_cell: Vector2i = result["target_cell"]
		if int(target_counts[target_cell]) > 1:
			valid_move_items[item] = false

	var changed: bool = true
	while changed:
		changed = false
		for item in valid_move_items.keys():
			if not bool(valid_move_items[item]):
				continue

			var result: Dictionary = item_results[item]
			var target_cell: Vector2i = result["target_cell"]
			var target_item: Item = item_snapshot.get(target_cell) as Item
			if target_item == null or not is_instance_valid(target_item) or target_item == item:
				continue

			if _is_item_vacating(target_item, item_results, valid_move_items):
				continue

			valid_move_items[item] = false
			changed = true

	for item in item_results.keys():
		var result: Dictionary = item_results[item]
		if String(result["action"]) != ITEM_RESULT_MOVE:
			continue

		if bool(valid_move_items.get(item, false)):
			continue

		result["action"] = ITEM_RESULT_STAY
		result.erase("target_cell")
		item_results[item] = result


func _is_item_vacating(item: Item, item_results: Dictionary, valid_move_items: Dictionary) -> bool:
	var result: Dictionary = item_results.get(item, {})
	var action: String = String(result.get("action", ITEM_RESULT_STAY))
	if action == ITEM_RESULT_ACCEPT or action == ITEM_RESULT_DESTROY:
		return true

	if action != ITEM_RESULT_MOVE:
		return false

	return bool(valid_move_items.get(item, false))


func _commit_items(item_results: Dictionary, beat_index: int) -> void:
	var successful_moves: Array[Dictionary] = []
	for item in item_results.keys():
		var result: Dictionary = item_results[item]
		var action: String = String(result["action"])
		if action == ITEM_RESULT_MOVE:
			successful_moves.append({
				"item": item,
				"target_cell": result["target_cell"],
				"flow_direction": result["flow_direction"],
			})
			continue

		if is_instance_valid(item):
			item.mark_resolved_on_beat(beat_index)

	for move_result in successful_moves:
		var item: Item = move_result["item"] as Item
		if item == null or not is_instance_valid(item):
			continue

		item.begin_parallel_move()

	for move_result in successful_moves:
		var item: Item = move_result["item"] as Item
		if item == null or not is_instance_valid(item):
			continue

		var target_cell: Vector2i = move_result["target_cell"]
		var flow_direction: Direction.Value = move_result["flow_direction"]
		item.complete_parallel_move(target_cell, flow_direction)
		item.mark_resolved_on_beat(beat_index)


func _commit_outputs(output_intents: Array[Dictionary], beat_index: int) -> void:
	var target_counts: Dictionary = {}
	for output_intent in output_intents:
		var target_cell: Vector2i = output_intent["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for output_intent in output_intents:
		var target_cell: Vector2i = output_intent["target_cell"]
		if int(target_counts[target_cell]) > 1:
			continue

		if _world.item_layer.has_cell(target_cell):
			continue

		var action: String = String(output_intent["action"])
		if action == OUTPUT_ACTION_SPAWN:
			var spawned_flow_direction: Direction.Value = output_intent["flow_direction"]
			var spawned_item: Item = _world.spawn_item(
				target_cell,
				String(output_intent["item_type"]),
				output_intent["item_kind"],
				spawned_flow_direction
			)
			if spawned_item == null:
				continue

			spawned_item.mark_resolved_on_beat(beat_index)
			_call_output_success(output_intent)
			continue

		if action == OUTPUT_ACTION_RELEASE:
			var released_item: Item = output_intent["item"] as Item
			if released_item == null or not is_instance_valid(released_item):
				continue

			var released_flow_direction: Direction.Value = output_intent["flow_direction"]
			if not released_item.deploy_from_machine(target_cell, released_flow_direction):
				continue

			released_item.mark_resolved_on_beat(beat_index)
			_call_output_success(output_intent)


func _call_output_success(output_intent: Dictionary) -> void:
	var on_success: Variant = output_intent.get("on_success", null)
	if not (on_success is Callable):
		return

	var success_callable: Callable = on_success
	if not success_callable.is_valid():
		return

	success_callable.call()
