extends Node2D
class_name Recycler

signal goal_completed(state: Dictionary)

const IDLE_COLOR: Color = Color(0.93, 0.28, 0.34, 1.0)
const COMPLETE_COLOR: Color = Color(0.27, 0.74, 0.42, 1.0)
const OUTLINE_COLOR: Color = Color(0.15, 0.09, 0.07, 1.0)
const COUNT_BG_COLOR: Color = Color(0.09, 0.11, 0.16, 0.92)
const COUNT_TEXT_COLOR: Color = Color(0.97, 0.95, 0.88, 1.0)
const COMPLETE_RING_COLOR: Color = Color(1.0, 0.93, 0.61, 1.0)

@export var targets: Array[Dictionary] = []:
	set(value):
		targets = _normalize_targets(value)
		_rebuild_target_states()
		_update_visual_state()

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
var _target_states: Array[Dictionary] = []
var _has_emitted_goal_completed: bool = false
var _font: Font
@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_world = GM.world
	_register_to_recycler_layer()
	_rebuild_target_states()
	_update_visual_state()


func _exit_tree() -> void:
	_unregister_from_recycler_layer()


func get_registered_cell() -> Vector2i:
	return _registered_cell


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


func collect_product(target_product: Item) -> bool:
	if target_product == null or not is_instance_valid(target_product) or not target_product.is_product():
		return false

	var normalized_product_type: String = CargoType.normalize(target_product.item_type)
	var target_index: int = _find_target_index(normalized_product_type)
	if target_index == -1:
		return false

	var target_status: Dictionary = _target_states[target_index]
	var remaining_count: int = int(target_status["remaining_count"])
	if remaining_count <= 0:
		return false

	var was_completed: bool = is_completed()
	target_product.remove_from_world()
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


func _register_to_recycler_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.recycler_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_recycler_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.recycler_layer.get_cell(_registered_cell) == self:
		_world.recycler_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func _update_visual_state() -> void:
	if _sprite != null:
		_sprite.modulate = COMPLETE_COLOR if is_completed() else IDLE_COLOR

	queue_redraw()


func _draw() -> void:
	_draw_count_badge()
	if is_completed():
		_draw_complete_ring()


func _draw_count_badge() -> void:
	var display_text: String = _get_badge_text()
	var font: Font = _get_draw_font()
	if font == null:
		return

	var font_size: int = 16
	var text_size: Vector2 = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var badge_size: Vector2 = Vector2(maxf(text_size.x + 18.0, 36.0), 28.0)
	var badge_position: Vector2 = Vector2(32.0 - badge_size.x * 0.5, -46.0)
	var badge_rect: Rect2 = Rect2(badge_position, badge_size)
	draw_rect(badge_rect, COUNT_BG_COLOR, true)
	draw_rect(badge_rect, OUTLINE_COLOR, false, 2.0)

	var text_position: Vector2 = Vector2(
		badge_rect.position.x + (badge_rect.size.x - text_size.x) * 0.5,
		badge_rect.position.y + badge_rect.size.y * 0.5 + text_size.y * 0.35
	)
	draw_string(font, text_position, display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COUNT_TEXT_COLOR)


func _draw_complete_ring() -> void:
	draw_arc(Vector2(32.0, 32.0), 24.0, 0.0, TAU, 24, COMPLETE_RING_COLOR, 3.0)


func _get_draw_font() -> Font:
	if _font != null:
		return _font

	_font = ThemeDB.fallback_font
	return _font


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


func _get_badge_text() -> String:
	if is_completed():
		return "OK"

	var effective_target_states: Array[Dictionary] = _get_effective_target_states()
	if effective_target_states.is_empty():
		return "--"

	var remaining_segments: Array[String] = []
	for target_status in effective_target_states:
		var remaining_count: int = int(target_status["remaining_count"])
		if remaining_count <= 0:
			continue

		remaining_segments.append("%s:%d" % [String(target_status["product_type"]), remaining_count])

	if remaining_segments.is_empty():
		return "--"

	return " ".join(remaining_segments)


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
