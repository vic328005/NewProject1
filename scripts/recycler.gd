extends Machine
class_name Recycler

signal goal_completed(state: Dictionary)

const IDLE_ANIMATION: StringName = &"idle"
const COMPLETE_RING_COLOR: Color = Color(1.0, 0.93, 0.61, 1.0)

@export var targets: Array[Dictionary] = []:
	set(value):
		targets = _normalize_targets(value)
		_rebuild_target_states()
		_update_visual_state()

var _target_states: Array[Dictionary] = []
var _has_emitted_goal_completed: bool = false
@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	super._ready()
	_play_idle_animation()
	_rebuild_target_states()
	_update_visual_state()


func _exit_tree() -> void:
	super._exit_tree()


func is_completed() -> bool:
	var effective_target_states: Array[Dictionary] = _get_effective_target_states()
	return not effective_target_states.is_empty() and get_remaining_total_count() <= 0


func can_accept_product(target_product_type: String) -> bool:
	if is_completed():
		return false

	var target_index: int = _find_target_index(CargoType.normalize(target_product_type))
	if target_index == -1:
		return false

	return int(_target_states[target_index]["remaining_count"]) > 0


func collect_product(product_type: String) -> bool:
	var normalized_product_type: String = CargoType.normalize(product_type)
	var target_index: int = _find_target_index(normalized_product_type)
	if target_index == -1:
		return false

	var target_status: Dictionary = _target_states[target_index]
	var remaining_count: int = int(target_status["remaining_count"])
	if remaining_count <= 0:
		return false

	var was_completed: bool = is_completed()
	target_status["remaining_count"] = remaining_count - 1
	target_status["completed_count"] = int(target_status["required_count"]) - int(target_status["remaining_count"])
	target_status["is_completed"] = int(target_status["remaining_count"]) <= 0
	_target_states[target_index] = target_status
	_update_visual_state()
	_log_status("collect_product", normalized_product_type)

	if not was_completed and is_completed() and not _has_emitted_goal_completed:
		_has_emitted_goal_completed = true
		var snapshot: Dictionary = get_status_snapshot()
		goal_completed.emit(snapshot)
		_log_status("goal_completed", normalized_product_type)

	return true


func log_cargo_destroyed(cargo_type: String) -> void:
	_log_status("destroy_cargo", CargoType.normalize(cargo_type))


func plan_output(_beat_index: int, _receives_signal: bool) -> Dictionary:
	return {
		"action": "none",
	}


func plan_transport(_item: Item, _beat_index: int, _receives_signal: bool) -> Dictionary:
	return {
		"action": "block",
	}


func plan_input(item: Item, _beat_index: int, _receives_signal: bool) -> Dictionary:
	if item == null or not is_instance_valid(item):
		return {
			"action": "reject",
		}

	if item.is_product() and can_accept_product(item.item_type):
		return {
			"action": "destroy",
			"product_type": CargoType.normalize(item.item_type),
			"counts_as_goal": true,
		}

	if item.is_cargo():
		return {
			"action": "destroy",
			"cargo_type": CargoType.normalize(item.item_type),
			"counts_as_goal": false,
		}

	return {
		"action": "destroy",
		"product_type": CargoType.normalize(item.item_type),
		"counts_as_goal": false,
	}


func get_total_required_count() -> int:
	var total_required_count: int = 0
	for target_status in _get_effective_target_states():
		total_required_count += int(target_status["required_count"])

	return total_required_count


func get_remaining_total_count() -> int:
	var remaining_total_count: int = 0
	for target_status in _get_effective_target_states():
		remaining_total_count += int(target_status["remaining_count"])

	return remaining_total_count


func get_target_statuses() -> Array[Dictionary]:
	return _get_effective_target_states().duplicate(true)


func get_status_snapshot() -> Dictionary:
	return {
		"cell": _registered_cell,
		"is_completed": is_completed(),
		"total_required_count": get_total_required_count(),
		"remaining_total_count": get_remaining_total_count(),
		"targets": get_target_statuses(),
	}


func _update_visual_state() -> void:
	queue_redraw()


func _draw() -> void:
	if is_completed():
		_draw_complete_ring()


func _draw_complete_ring() -> void:
	draw_arc(Vector2(32.0, 32.0), 24.0, 0.0, TAU, 24, COMPLETE_RING_COLOR, 3.0)


func _play_idle_animation() -> void:
	assert(_animated_sprite != null, "Recycler must have an AnimatedSprite2D child.")
	assert(_animated_sprite.sprite_frames != null, "Recycler AnimatedSprite2D must have SpriteFrames assigned.")

	var animation_names: PackedStringArray = _animated_sprite.sprite_frames.get_animation_names()
	assert(animation_names.size() == 1 and animation_names[0] == String(IDLE_ANIMATION), "Recycler must only define the idle animation.")

	_animated_sprite.animation = IDLE_ANIMATION
	_animated_sprite.play(IDLE_ANIMATION)


func _normalize_targets(raw_targets: Array) -> Array[Dictionary]:
	var normalized_targets: Array[Dictionary] = []
	var seen_product_types: Dictionary = {}
	for raw_target in raw_targets:
		assert(typeof(raw_target) == TYPE_DICTIONARY, "Recycler targets entries must be dictionaries.")

		var target: Dictionary = raw_target
		assert(target.has("product_type"), "Recycler target must contain product_type.")
		assert(target.has("required_count"), "Recycler target must contain required_count.")

		var product_type: String = CargoType.normalize(target["product_type"])
		assert(CargoType.is_valid(product_type), "Recycler target product_type must be valid.")
		assert(not seen_product_types.has(product_type), "Recycler target product_type must be unique.")

		var required_count: int = int(target["required_count"])
		assert(required_count > 0, "Recycler target required_count must be positive.")
		seen_product_types[product_type] = true

		normalized_targets.append({
			"product_type": product_type,
			"required_count": required_count,
		})

	return normalized_targets


func _rebuild_target_states() -> void:
	_target_states = _create_target_states_from_targets(targets)
	_has_emitted_goal_completed = false


func _find_target_index(product_type: String) -> int:
	for index in range(_target_states.size()):
		if String(_target_states[index]["product_type"]) == product_type:
			return index

	return -1


func _get_effective_target_states() -> Array[Dictionary]:
	if not _target_states.is_empty():
		return _target_states

	return _create_target_states_from_targets(targets)


func _log_status(event_name: String, item_type: String) -> void:
	print(
		"[Recycler] cell=%s event=%s item_type=%s status=%s" % [
			str(_registered_cell),
			event_name,
			item_type,
			_get_log_status_summary(),
		]
	)


func _get_log_status_summary() -> String:
	return str({
		"remaining_total_count": get_remaining_total_count(),
		"targets": get_target_statuses(),
	})


func _create_target_states_from_targets(source_targets: Array[Dictionary]) -> Array[Dictionary]:
	var target_states: Array[Dictionary] = []
	for target in source_targets:
		var required_count: int = int(target["required_count"])
		target_states.append({
			"product_type": String(target["product_type"]),
			"required_count": required_count,
			"remaining_count": required_count,
			"completed_count": 0,
			"is_completed": false,
		})

	return target_states
