class_name World
extends Node2D

var main_layer: MapLayer
var cargo_layer: MapLayer


func _init() -> void:
	main_layer = _create_layer()
	cargo_layer = _create_layer()


func world_to_cell(world_position: Vector2) -> Vector2i:
	return main_layer.world_to_cell(world_position)


func cell_to_world(cell: Vector2i) -> Vector2:
	return main_layer.cell_to_world(cell)


func _create_layer() -> MapLayer:
	var layer := MapLayer.new()
	layer.cell_size = 64
	return layer
