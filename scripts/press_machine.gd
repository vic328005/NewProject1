@tool
extends Machine
class_name PressMachine

const PREVIEW_CELL_SIZE: float = 64.0
const PREVIEW_CENTER: Vector2 = Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.5)
const DEFAULT_CARGO_TYPE: String = CargoType.DEFAULT
const DEFAULT_BEAT_INTERVAL: int = 2
const BASE_COLOR: Color = Color(0.94, 0.82, 0.30, 1.0)
const SHAPE_COLOR_1: Color = Color(0.96, 0.89, 0.72, 1.0)
const SHAPE_COLOR_2: Color = Color(0.64, 0.92, 0.73, 1.0)
const SHAPE_COLOR_3: Color = Color(0.62, 0.56, 0.98, 1.0)

@export var facing: Direction.Value = Direction.Value.RIGHT:
	set(value):
		facing = value
		_update_sprite_visual()
		queue_redraw()

@export var cargo_type: String = DEFAULT_CARGO_TYPE:
	set(value):
		cargo_type = CargoType.normalize(value)
		_update_sprite_visual()
		queue_redraw()

@export_range(1, 2, 1) var beat_interval: int = DEFAULT_BEAT_INTERVAL:
	set(value):
		beat_interval = clampi(value, 1, 2)
		_update_sprite_visual()
		queue_redraw()

var _pressed_item: Item
var _press_start_beat: int = -1
var _output_ready_beat: int = -1
var _sprite: Sprite2D


func _ready() -> void:
	_update_sprite_visual()
	queue_redraw()
	super._ready()


func _exit_tree() -> void:
	super._exit_tree()


func get_target_cell() -> Vector2i:
	return _registered_cell + Direction.to_vector2i(facing)


func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % beat_interval == 0


func plan_output(beat_index: int, _receives_signal: bool) -> Dictionary:
	if not _has_valid_pressed_item():
		return {
			"action": "none",
		}

	if _output_ready_beat < 0 or beat_index < _output_ready_beat:
		return {
			"action": "none",
		}

	return {
		"action": "release",
		"target_cell": get_target_cell(),
		"item": _pressed_item,
		"flow_direction": facing,
	}


func plan_transport(item: Item, beat_index: int, receives_signal: bool) -> Dictionary:
	if _has_valid_pressed_item():
		return {
			"action": "block",
		}

	if item.is_cargo() and _is_triggered_on_beat(beat_index, receives_signal):
		return {
			"action": "block",
		}

	return {
		"action": "move",
		"target_cell": get_target_cell(),
		"flow_direction": facing,
	}


func plan_input(item: Item, beat_index: int, receives_signal: bool) -> Dictionary:
	if item == null or not is_instance_valid(item):
		return {
			"action": "reject",
		}

	if not item.is_cargo():
		return {
			"action": "reject",
		}

	if not _is_triggered_on_beat(beat_index, receives_signal):
		return {
			"action": "reject",
		}

	if _has_valid_pressed_item():
		return {
			"action": "reject",
		}

	return {
		"action": "accept",
	}


func clear_pressed_item() -> void:
	_pressed_item = null
	_press_start_beat = -1
	_output_ready_beat = -1


func _should_register_to_machine_layer() -> bool:
	return not Engine.is_editor_hint()


func _has_valid_pressed_item() -> bool:
	return _pressed_item != null and is_instance_valid(_pressed_item)


func _update_sprite_visual() -> void:
	if _sprite == null:
		_sprite = get_node_or_null(^"Sprite2D") as Sprite2D

	if _sprite == null:
		return

	_sprite.modulate = BASE_COLOR


func _draw() -> void:
	var shape_color: Color = _get_shape_color()
	var arrow_tip: Vector2 = PREVIEW_CENTER + _direction_to_vector(facing) * 16.0
	var arrow_tail: Vector2 = PREVIEW_CENTER - _direction_to_vector(facing) * 8.0
	draw_line(arrow_tail, arrow_tip, Color(0.18, 0.14, 0.08, 1.0), 4.0)
	_draw_arrow_head(arrow_tip, _direction_to_vector(facing))

	match cargo_type:
		CargoType.B:
			draw_circle(PREVIEW_CENTER, 12.0, shape_color)
			draw_arc(PREVIEW_CENTER, 12.0, 0.0, TAU, 24, Color.BLACK, 2.0)
		CargoType.C:
			draw_rect(Rect2(PREVIEW_CENTER - Vector2.ONE * 11.0, Vector2.ONE * 22.0), shape_color, true)
			draw_rect(Rect2(PREVIEW_CENTER - Vector2.ONE * 11.0, Vector2.ONE * 22.0), Color.BLACK, false, 2.0)
		_:
			var triangle_points: PackedVector2Array = PackedVector2Array([
				PREVIEW_CENTER + Vector2(0.0, -14.0),
				PREVIEW_CENTER + Vector2(13.0, 11.0),
				PREVIEW_CENTER + Vector2(-13.0, 11.0),
			])
			var closed_triangle_points: PackedVector2Array = PackedVector2Array([
				triangle_points[0],
				triangle_points[1],
				triangle_points[2],
				triangle_points[0],
			])
			draw_colored_polygon(triangle_points, shape_color)
			draw_polyline(closed_triangle_points, Color.BLACK, 2.0)


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
		Color(0.18, 0.14, 0.08, 1.0)
	)


func _direction_to_vector(direction: Direction.Value) -> Vector2:
	match direction:
		Direction.Value.UP:
			return Vector2.UP
		Direction.Value.RIGHT:
			return Vector2.RIGHT
		Direction.Value.DOWN:
			return Vector2.DOWN
		_:
			return Vector2.LEFT


func _get_shape_color() -> Color:
	match cargo_type:
		CargoType.B:
			return SHAPE_COLOR_2
		CargoType.C:
			return SHAPE_COLOR_3
		_:
			return SHAPE_COLOR_1


func _is_triggered_on_beat(beat_index: int, receives_signal: bool) -> bool:
	if not receives_signal:
		return false

	return should_trigger_on_beat(beat_index)
