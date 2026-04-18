class_name World
extends Node2D

var main_layer: MapLayer
var cargo_layer: MapLayer
var belt_layer: MapLayer
var _beat_conductor: BeatConductor


func _init() -> void:
	main_layer = _create_layer()
	cargo_layer = _create_layer()
	belt_layer = _create_layer()


func _enter_tree() -> void:
	if is_instance_valid(GM.current_world) and GM.current_world != self:
		push_error("Only one World instance is allowed.")
		queue_free()
		return

	GM.current_world = self


func _ready() -> void:
	if GM.current_world != self:
		return

	_beat_conductor = GM.beat_conductor

	if not _beat_conductor.beat_fired.is_connected(_on_beat_fired):
		_beat_conductor.beat_fired.connect(_on_beat_fired)


func _exit_tree() -> void:
	if is_instance_valid(_beat_conductor) and _beat_conductor.beat_fired.is_connected(_on_beat_fired):
		_beat_conductor.beat_fired.disconnect(_on_beat_fired)

	if GM.current_world == self:
		GM.current_world = null


func world_to_cell(world_position: Vector2) -> Vector2i:
	return main_layer.world_to_cell(world_position)


func cell_to_world(cell: Vector2i) -> Vector2:
	return main_layer.cell_to_world(cell)


func _create_layer() -> MapLayer:
	var layer := MapLayer.new()
	layer.cell_size = 64
	return layer


func _on_beat_fired(beat_index: int, _beat_time: float) -> void:
	_resolve_belt_moves(beat_index)


func _resolve_belt_moves(beat_index: int) -> void:
	var belt_cells := belt_layer.get_cells()
	var occupied_cells := cargo_layer.get_cells()
	var requests: Array[Dictionary] = []
	var target_counts: Dictionary = {}

	for cell in belt_cells.keys():
		var belt := belt_cells[cell] as Belt

		if belt == null or not is_instance_valid(belt):
			continue

		if not belt.should_trigger_on_beat(beat_index):
			continue

		var cargo := occupied_cells.get(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		var target_cell := belt.get_target_cell()
		requests.append({
			"cargo": cargo,
			"target_cell": target_cell,
		})
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in requests:
		var target_cell: Vector2i = request["target_cell"]

		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if occupied_cells.has(target_cell):
			continue

		var cargo: Cargo = request["cargo"]
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.move_to_cell(target_cell)
