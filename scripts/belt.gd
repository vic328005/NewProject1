@tool
extends Node2D
class_name Belt

enum Direction {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

enum TurnMode {
	STRAIGHT,
	LEFT,
	RIGHT,
}

const PREVIEW_CELL_SIZE := 64.0
const PREVIEW_CENTER := Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.5)

@export var facing: Direction = Direction.RIGHT:
	set(value):
		facing = value
		queue_redraw()

@export var turn_mode: TurnMode = TurnMode.STRAIGHT:
	set(value):
		turn_mode = value
		queue_redraw()

@export_range(1, 2, 1) var beat_interval := 2:
	set(value):
		beat_interval = clampi(value, 1, 2)
		queue_redraw()

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer := false


func _ready() -> void:
	queue_redraw()

	if Engine.is_editor_hint():
		return

	_world = GM.current_world
	_register_to_belt_layer()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	_unregister_from_belt_layer()


func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % beat_interval == 0


func get_registered_cell() -> Vector2i:
	return _registered_cell


func get_target_cell() -> Vector2i:
	return _registered_cell + _direction_to_offset(_get_output_direction())


func _register_to_belt_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.belt_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_belt_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.belt_layer.get_cell(_registered_cell) == self:
		_world.belt_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func _get_output_direction() -> Direction:
	match turn_mode:
		TurnMode.LEFT:
			return wrapi(int(facing) - 1, 0, 4) as Direction
		TurnMode.RIGHT:
			return wrapi(int(facing) + 1, 0, 4) as Direction
		_:
			return facing


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

#
#func _draw() -> void:
#	var rect := Rect2(Vector2.ZERO, Vector2.ONE * PREVIEW_CELL_SIZE)
#	var fill_color := Color(0.20, 0.52, 0.78, 0.85)
#
#	if beat_interval == 1:
#		fill_color = Color(0.88, 0.48, 0.18, 0.9)
#
#	draw_rect(rect, fill_color, true)
#	draw_rect(rect, Color(0.08, 0.12, 0.16, 0.95), false, 2.0)
#
#	var points := PackedVector2Array()
#	match turn_mode:
#		TurnMode.LEFT:
#			points = PackedVector2Array([
#				Vector2(PREVIEW_CELL_SIZE * 0.22, PREVIEW_CELL_SIZE * 0.5),
#				Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.5),
#				Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.22),
#			])
#		TurnMode.RIGHT:
#			points = PackedVector2Array([
#				Vector2(PREVIEW_CELL_SIZE * 0.22, PREVIEW_CELL_SIZE * 0.5),
#				Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.5),
#				Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.78),
#			])
#		_:
#			points = PackedVector2Array([
#				Vector2(PREVIEW_CELL_SIZE * 0.22, PREVIEW_CELL_SIZE * 0.5),
#				Vector2(PREVIEW_CELL_SIZE * 0.78, PREVIEW_CELL_SIZE * 0.5),
#			])
#
#	for index in range(points.size()):
#		points[index] = (points[index] - PREVIEW_CENTER).rotated(float(facing) * PI * 0.5) + PREVIEW_CENTER
#
#	draw_polyline(points, Color.WHITE, 6.0)
#
#	var tip := points[points.size() - 1]
#	var tail := points[points.size() - 2]
#	var arrow_direction := (tip - tail).normalized()
#	var arrow_normal := Vector2(-arrow_direction.y, arrow_direction.x)
#	var arrow_size := 10.0
#	draw_colored_polygon(
#		PackedVector2Array([
#			tip,
#			tip - arrow_direction * arrow_size + arrow_normal * (arrow_size * 0.6),
#			tip - arrow_direction * arrow_size - arrow_normal * (arrow_size * 0.6),
#		]),
#		Color.WHITE
#	)
