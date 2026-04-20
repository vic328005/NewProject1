@tool
extends Node2D
class_name Sorter

enum OutputSide {
	LEFT,
	RIGHT,
}

const PREVIEW_CELL_SIZE: float = 64.0
const PREVIEW_CENTER: Vector2 = Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.5)
const BASE_COLOR: Color = Color(0.32, 0.66, 0.84, 1.0)
const ACTIVE_PATH_COLOR: Color = Color(0.95, 0.95, 0.98, 1.0)
const INACTIVE_PATH_COLOR: Color = Color(0.56, 0.74, 0.84, 1.0)
const OUTLINE_COLOR: Color = Color(0.12, 0.16, 0.20, 1.0)

@export var input_direction: Direction.Value = Direction.Value.UP:
	set(value):
		input_direction = value
		_update_sprite_visual()
		queue_redraw()

@export var initial_output_side: OutputSide = OutputSide.LEFT:
	set(value):
		initial_output_side = value
		_current_output_side = initial_output_side
		_update_sprite_visual()
		queue_redraw()

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
var _current_output_side: OutputSide = OutputSide.LEFT
var _sprite: Sprite2D


func _ready() -> void:
	_current_output_side = initial_output_side
	_update_sprite_visual()
	queue_redraw()

	if Engine.is_editor_hint():
		return

	_world = GM.world
	_register_to_sorter_layer()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	_unregister_from_sorter_layer()


func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % 2 == 0


func get_registered_cell() -> Vector2i:
	return _registered_cell


func get_target_cell() -> Vector2i:
	return _registered_cell + Direction.to_vector2i(_get_output_direction())


func toggle_output() -> void:
	# 信号命中时只切一次，下一次运输直接读取切换后的方向。
	if _current_output_side == OutputSide.LEFT:
		_current_output_side = OutputSide.RIGHT
	else:
		_current_output_side = OutputSide.LEFT

	_update_sprite_visual()
	queue_redraw()


func _register_to_sorter_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.sorter_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_sorter_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.sorter_layer.get_cell(_registered_cell) == self:
		_world.sorter_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func _get_output_direction() -> Direction.Value:
	if _current_output_side == OutputSide.LEFT:
		return Direction.rotate_left(input_direction)

	return Direction.rotate_right(input_direction)


func _direction_to_rotation(direction: Direction.Value) -> float:
	match direction:
		Direction.Value.UP:
			return 0.0
		Direction.Value.RIGHT:
			return PI * 0.5
		Direction.Value.DOWN:
			return PI
		_:
			return PI * 1.5


func _update_sprite_visual() -> void:
	if _sprite == null:
		_sprite = get_node_or_null(^"Sprite2D") as Sprite2D

	if _sprite == null:
		return

	_sprite.modulate = BASE_COLOR


func _draw() -> void:
	var rotation_radians: float = _direction_to_rotation(input_direction)
	var input_start: Vector2 = _rotate_local_point(Vector2(32.0, 10.0), rotation_radians)
	var center: Vector2 = PREVIEW_CENTER
	var left_end: Vector2 = _rotate_local_point(Vector2(14.0, 52.0), rotation_radians)
	var right_end: Vector2 = _rotate_local_point(Vector2(50.0, 52.0), rotation_radians)

	draw_line(input_start, center, ACTIVE_PATH_COLOR, 8.0)
	draw_line(input_start, center, OUTLINE_COLOR, 2.0)

	var left_color: Color = ACTIVE_PATH_COLOR if _current_output_side == OutputSide.LEFT else INACTIVE_PATH_COLOR
	var right_color: Color = ACTIVE_PATH_COLOR if _current_output_side == OutputSide.RIGHT else INACTIVE_PATH_COLOR

	draw_line(center, left_end, left_color, 8.0)
	draw_line(center, left_end, OUTLINE_COLOR, 2.0)
	draw_line(center, right_end, right_color, 8.0)
	draw_line(center, right_end, OUTLINE_COLOR, 2.0)

	_draw_arrow_head(left_end, (left_end - center).normalized(), left_color)
	_draw_arrow_head(right_end, (right_end - center).normalized(), right_color)


func _rotate_local_point(point: Vector2, rotation_radians: float) -> Vector2:
	return (point - PREVIEW_CENTER).rotated(rotation_radians) + PREVIEW_CENTER


func _draw_arrow_head(tip: Vector2, direction: Vector2, fill_color: Color) -> void:
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var arrow_size: float = 7.0
	var points: PackedVector2Array = PackedVector2Array([
		tip,
		tip - direction * arrow_size + normal * (arrow_size * 0.6),
		tip - direction * arrow_size - normal * (arrow_size * 0.6),
	])
	draw_colored_polygon(points, fill_color)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), OUTLINE_COLOR, 2.0)
