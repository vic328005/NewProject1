@tool
extends Node2D
class_name Refiner

enum Direction {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

const PREVIEW_CELL_SIZE: float = 64.0
const PREVIEW_CENTER: Vector2 = Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.5)
const BASE_COLOR: Color = Color(0.82, 0.88, 0.94, 1.0)
const BODY_COLOR: Color = Color(0.94, 0.97, 1.0, 1.0)
const ACCENT_COLOR: Color = Color(0.35, 0.56, 0.78, 1.0)
const COUNTER_FILL_COLOR: Color = Color(0.18, 0.24, 0.30, 1.0)
const COUNTER_TEXT_COLOR: Color = Color(0.98, 0.96, 0.86, 1.0)
const OUTLINE_COLOR: Color = Color(0.12, 0.16, 0.20, 1.0)

@export var facing: Direction = Direction.RIGHT:
	set(value):
		facing = value
		_update_sprite_visual()
		queue_redraw()

var remaining_signal_hits: int = 2
var last_signal_beat: int = -1
var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
var _sprite: Sprite2D
var _reset_after_trigger: bool = false


func _ready() -> void:
	_update_sprite_visual()
	queue_redraw()

	if Engine.is_editor_hint():
		return

	_world = GM.world
	_register_to_refiner_layer()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	_unregister_from_refiner_layer()


func get_registered_cell() -> Vector2i:
	return _registered_cell


func get_target_cell() -> Vector2i:
	return _registered_cell + _direction_to_offset(facing)


func resolve_signal_state(beat_index: int, has_signal: bool) -> bool:
	# 触发后的 0 会保留到下一拍开始，再恢复成 2。
	if _reset_after_trigger and beat_index > last_signal_beat:
		_reset_signal_chain()

	if has_signal:
		if remaining_signal_hits == 1 and last_signal_beat == beat_index - 1:
			remaining_signal_hits = 0
			last_signal_beat = beat_index
			_reset_after_trigger = true
			queue_redraw()
			return true

		remaining_signal_hits = 1
		last_signal_beat = beat_index
		_reset_after_trigger = false
		queue_redraw()
		return false

	if remaining_signal_hits == 1 and beat_index > last_signal_beat:
		_reset_signal_chain()

	return false


func get_refined_cargo_type(cargo_type: String) -> String:
	match String(cargo_type).strip_edges().to_upper():
		"CARGO_1":
			return "ADV_CARGO_1"
		"CARGO_2":
			return "ADV_CARGO_2"
		"CARGO_3":
			return "ADV_CARGO_3"
		_:
			return String(cargo_type).strip_edges().to_upper()


func _reset_signal_chain() -> void:
	remaining_signal_hits = 2
	last_signal_beat = -1
	_reset_after_trigger = false
	queue_redraw()


func _register_to_refiner_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.refiner_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_refiner_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.refiner_layer.get_cell(_registered_cell) == self:
		_world.refiner_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func _direction_to_offset(direction: Direction) -> Vector2i:
	match direction:
		Direction.UP:
			return Vector2i.UP
		Direction.RIGHT:
			return Vector2i.RIGHT
		Direction.DOWN:
			return Vector2i.DOWN
		_:
			return Vector2i.LEFT


func _direction_to_vector(direction: Direction) -> Vector2:
	match direction:
		Direction.UP:
			return Vector2.UP
		Direction.RIGHT:
			return Vector2.RIGHT
		Direction.DOWN:
			return Vector2.DOWN
		_:
			return Vector2.LEFT


func _update_sprite_visual() -> void:
	if _sprite == null:
		_sprite = get_node_or_null(^"Sprite2D") as Sprite2D

	if _sprite == null:
		return

	_sprite.modulate = BASE_COLOR


func _draw() -> void:
	var chamber_rect: Rect2 = Rect2(PREVIEW_CENTER - Vector2(14.0, 10.0), Vector2(28.0, 24.0))
	draw_rect(chamber_rect, BODY_COLOR, true)
	draw_rect(chamber_rect, OUTLINE_COLOR, false, 2.0)

	var arrow_direction: Vector2 = _direction_to_vector(facing)
	var arrow_tail: Vector2 = PREVIEW_CENTER + arrow_direction * 4.0
	var arrow_tip: Vector2 = PREVIEW_CENTER + arrow_direction * 20.0
	draw_line(arrow_tail, arrow_tip, ACCENT_COLOR, 5.0)
	_draw_arrow_head(arrow_tip, arrow_direction)

	var counter_rect: Rect2 = Rect2(Vector2(20.0, 6.0), Vector2(24.0, 16.0))
	draw_rect(counter_rect, COUNTER_FILL_COLOR, true)
	draw_rect(counter_rect, OUTLINE_COLOR, false, 2.0)
	_draw_counter_digit(counter_rect, remaining_signal_hits)


func _draw_arrow_head(tip: Vector2, direction: Vector2) -> void:
	var normalized_direction: Vector2 = direction.normalized()
	var normal: Vector2 = Vector2(-normalized_direction.y, normalized_direction.x)
	var arrow_size: float = 8.0
	draw_colored_polygon(
		PackedVector2Array([
			tip,
			tip - normalized_direction * arrow_size + normal * (arrow_size * 0.6),
			tip - normalized_direction * arrow_size - normal * (arrow_size * 0.6),
		]),
		ACCENT_COLOR
	)


func _draw_counter_digit(counter_rect: Rect2, digit: int) -> void:
	var left: float = counter_rect.position.x + 6.0
	var right: float = counter_rect.end.x - 6.0
	var top: float = counter_rect.position.y + 3.0
	var middle: float = counter_rect.position.y + counter_rect.size.y * 0.5
	var bottom: float = counter_rect.end.y - 3.0
	var center_x: float = counter_rect.position.x + counter_rect.size.x * 0.5
	var line_width: float = 3.0

	match digit:
		0:
			draw_line(Vector2(left, top), Vector2(right, top), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(right, top), Vector2(right, bottom), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(right, bottom), Vector2(left, bottom), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(left, bottom), Vector2(left, top), COUNTER_TEXT_COLOR, line_width)
		1:
			draw_line(Vector2(center_x, top), Vector2(center_x, bottom), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(center_x - 3.0, top + 2.0), Vector2(center_x, top), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(center_x - 5.0, bottom), Vector2(center_x + 5.0, bottom), COUNTER_TEXT_COLOR, line_width)
		_:
			draw_line(Vector2(left, top), Vector2(right, top), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(right, top), Vector2(right, middle), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(right, middle), Vector2(left, middle), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(left, middle), Vector2(left, bottom), COUNTER_TEXT_COLOR, line_width)
			draw_line(Vector2(left, bottom), Vector2(right, bottom), COUNTER_TEXT_COLOR, line_width)
