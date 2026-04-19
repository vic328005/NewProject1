extends Node2D
class_name SignalWave

const WAVE_FILL_COLOR: Color = Color(0.30, 0.69, 0.35, 0.38)
const WAVE_BORDER_COLOR: Color = Color(0.18, 0.41, 0.20, 0.9)
const DEFAULT_MAX_STEPS: int = 10

var max_steps: int = DEFAULT_MAX_STEPS

var _world: Node
var _origin_cell: Vector2i
var _wave_radius: int = 0
var _last_wave_beat_index: int = -1
var _is_finished: bool = false
var _wave_cells: Array[Vector2i] = []


func setup(world: Node, origin_cell: Vector2i, signal_max_steps: int, current_beat_index: int) -> void:
	assert(world != null, "SignalWave requires a World instance.")
	_world = world
	_origin_cell = origin_cell
	max_steps = maxi(signal_max_steps, 1)
	position = _world.cell_to_world(_origin_cell)
	_wave_radius = 1
	_last_wave_beat_index = current_beat_index
	_wave_cells = _build_wave_cells(_wave_radius)
	_is_finished = _wave_cells.is_empty()
	queue_redraw()


func advance(current_beat_index: int) -> void:
	if _world == null or _is_finished:
		return

	if current_beat_index <= _last_wave_beat_index:
		return

	if _wave_radius >= max_steps:
		_is_finished = true
		return

	var next_wave_radius: int = _wave_radius + 1
	_last_wave_beat_index = current_beat_index

	_wave_radius = next_wave_radius
	_wave_cells = _build_wave_cells(_wave_radius)
	queue_redraw()


func is_finished() -> bool:
	return _is_finished


func get_wave_cells() -> Array[Vector2i]:
	return _wave_cells.duplicate()


func remove_from_world() -> void:
	queue_free()


func _draw() -> void:
	if _world == null or _wave_cells.is_empty():
		return

	var cell_size: float = float(_world.main_layer.cell_size)
	var cell_extent: Vector2 = Vector2.ONE * cell_size

	for cell in _wave_cells:
		var cell_origin: Vector2 = _cell_to_local_origin(cell, cell_size)
		var cell_rect: Rect2 = Rect2(cell_origin, cell_extent)
		draw_rect(cell_rect, WAVE_FILL_COLOR, true)
		draw_rect(cell_rect, WAVE_BORDER_COLOR, false, 2.0)


func _build_wave_cells(radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var seen_cells: Dictionary = {}
	_append_wave_cell(_origin_cell, cells, seen_cells)

	var left: int = _origin_cell.x - radius
	var right: int = _origin_cell.x + radius
	var top: int = _origin_cell.y - radius
	var bottom: int = _origin_cell.y + radius

	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			if x != left and x != right and y != top and y != bottom:
				continue

			var cell: Vector2i = Vector2i(x, y)
			_append_wave_cell(cell, cells, seen_cells)

	return cells


func _append_wave_cell(cell: Vector2i, cells: Array[Vector2i], seen_cells: Dictionary) -> void:
	if seen_cells.has(cell):
		return

	seen_cells[cell] = true
	cells.append(cell)


func _cell_to_local_origin(cell: Vector2i, cell_size: float) -> Vector2:
	var offset: Vector2i = cell - _origin_cell
	return Vector2(float(offset.x) * cell_size, float(offset.y) * cell_size)
