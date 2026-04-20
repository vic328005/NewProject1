@tool
extends Node2D
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

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
var _pressed_cargo: Cargo
var _press_start_beat: int = -1
var _is_pressing: bool = false
var _output_ready_beat: int = -1
var _sprite: Sprite2D


func _ready() -> void:
	_update_sprite_visual()
	queue_redraw()

	if Engine.is_editor_hint():
		return

	_world = GM.world
	_register_to_press_machine_layer()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	_unregister_from_press_machine_layer()


func get_registered_cell() -> Vector2i:
	return _registered_cell


func get_target_cell() -> Vector2i:
	return _registered_cell + Direction.to_vector2i(facing)


func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % beat_interval == 0


func is_pressing() -> bool:
	if _has_invalid_pressed_cargo():
		clear_pressed_cargo()

	return _is_pressing


func get_pressed_cargo() -> Cargo:
	if not _has_valid_pressed_cargo():
		return null

	return _pressed_cargo


func has_finished_press(current_beat_index: int) -> bool:
	_refresh_output_state(current_beat_index)
	return _has_valid_pressed_cargo() and not _is_pressing and _output_ready_beat >= 0


func has_pending_output() -> bool:
	return _has_valid_pressed_cargo() and _output_ready_beat >= 0


func can_output_on_beat(beat_index: int) -> bool:
	_refresh_output_state(beat_index)
	return has_pending_output() and not _is_pressing and beat_index >= _output_ready_beat


func can_accept_input(is_triggered: bool) -> bool:
	return is_triggered and not _has_valid_pressed_cargo()


func accept_input(cargo: Cargo) -> void:
	assert(cargo != null and is_instance_valid(cargo), "PressMachine requires a valid Cargo to accept input.")
	assert(not _has_valid_pressed_cargo(), "PressMachine cannot accept input while occupied.")
	cargo.store_in_machine(global_position)
	_pressed_cargo = cargo
	_press_start_beat = -1
	_output_ready_beat = -1
	_is_pressing = false


func can_start_cycle(beat_index: int, is_triggered: bool) -> bool:
	_refresh_output_state(beat_index)
	return is_triggered and _has_valid_pressed_cargo() and not _is_pressing and _output_ready_beat < 0


func release_output(target_cell: Vector2i) -> Cargo:
	if not _has_valid_pressed_cargo():
		return null

	var cargo: Cargo = _pressed_cargo
	if not cargo.deploy_from_machine(target_cell):
		return null

	clear_pressed_cargo()
	return cargo


func allows_pass_through(item: TransportItem, is_triggered: bool, beat_index: int) -> bool:
	_refresh_output_state(beat_index)
	if _has_valid_pressed_cargo():
		return false

	if item is Cargo and is_triggered:
		return false

	return true


func begin_press(cargo: Cargo, beat_index: int) -> void:
	assert(cargo != null and is_instance_valid(cargo), "PressMachine requires a valid Cargo to start pressing.")
	assert(_pressed_cargo == cargo, "PressMachine can only start pressing its held Cargo.")
	assert(not _is_pressing, "PressMachine cannot start pressing while busy.")
	_pressed_cargo = cargo
	_press_start_beat = beat_index
	_output_ready_beat = beat_index + 1
	_is_pressing = true


func clear_pressed_cargo() -> void:
	_pressed_cargo = null
	_press_start_beat = -1
	_output_ready_beat = -1
	_is_pressing = false


func _has_valid_pressed_cargo() -> bool:
	return _pressed_cargo != null and is_instance_valid(_pressed_cargo)


func _has_invalid_pressed_cargo() -> bool:
	return _pressed_cargo != null and not is_instance_valid(_pressed_cargo)


func _refresh_output_state(beat_index: int) -> void:
	if _has_invalid_pressed_cargo():
		clear_pressed_cargo()
		return

	if not _has_valid_pressed_cargo():
		return

	if _is_pressing and _output_ready_beat >= 0 and beat_index >= _output_ready_beat:
		_is_pressing = false


func _register_to_press_machine_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.press_machine_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_press_machine_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.press_machine_layer.get_cell(_registered_cell) == self:
		_world.press_machine_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


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
