class_name MapLayer
extends RefCounted

# 只存非空格子，适合稀疏二维网格。
var _cells: Dictionary = {}

var cell_size: int = 64:
	set(value):
		cell_size = value if value > 0 else 64


func set_cell(cell: Vector2i, value: Variant) -> void:
	_cells[cell] = value


func get_cell(cell: Vector2i, default_value: Variant = null) -> Variant:
	return _cells.get(cell, default_value)


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


func erase_cell(cell: Vector2i) -> void:
	_cells.erase(cell)


func clear() -> void:
	_cells.clear()


func get_cells() -> Dictionary:
	return _cells


func world_to_cell(position: Vector2) -> Vector2i:
	var cell_x := int(floor(position.x / float(cell_size)))
	var cell_y := int(floor(position.y / float(cell_size)))
	return Vector2i(cell_x, cell_y)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size, cell.y * cell_size)
