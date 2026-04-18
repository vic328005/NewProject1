class_name World
extends Node2D

const CARGO_SCENE: PackedScene = preload("res://prefabs/cargo.tscn")

var main_layer: MapLayer
var cargo_layer: MapLayer
var belt_layer: MapLayer
var producer_layer: MapLayer
var recycler_layer: MapLayer
var signal_tower_layer: MapLayer
var level_id: String = ""
var display_name: String = ""
var grid_width: int = 0
var grid_height: int = 0
var _active_signals: Array = []
var _last_signal_emit_beat_index: int = -1
var _beats: BeatConductor
var _config: Config


func _init(config: Config) -> void:
	assert(config != null, "World requires a Config instance.")
	_config = config
	main_layer = _create_layer()
	cargo_layer = _create_layer()
	belt_layer = _create_layer()
	producer_layer = _create_layer()
	recycler_layer = _create_layer()
	signal_tower_layer = _create_layer()


func _enter_tree() -> void:
	if is_instance_valid(GM.world) and GM.world != self:
		push_error("Only one World instance is allowed.")
		queue_free()
		return

	GM.world = self


func _ready() -> void:
	if GM.world != self:
		return

	_beats = GM.beats

	if not _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.connect(_on_beat_fired)


func _exit_tree() -> void:
	if is_instance_valid(_beats) and _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.disconnect(_on_beat_fired)

	if GM.world == self:
		GM.world = null


func world_to_cell(world_position: Vector2) -> Vector2i:
	return main_layer.world_to_cell(world_position)


func cell_to_world(cell: Vector2i) -> Vector2:
	return main_layer.cell_to_world(cell)


func get_level_center() -> Vector2:
	if grid_width <= 0 or grid_height <= 0:
		return Vector2.ZERO

	var last_cell_origin: Vector2 = cell_to_world(Vector2i(grid_width - 1, grid_height - 1))
	var half_cell_size: float = float(main_layer.cell_size) * 0.5
	var center_offset: Vector2 = Vector2(half_cell_size, half_cell_size)
	return last_cell_origin * 0.5 + center_offset


func clear_level_content() -> void:
	for child in get_children():
		if child.is_in_group("runtime_level_content"):
			remove_child(child)
			child.queue_free()

	main_layer.clear()
	cargo_layer.clear()
	belt_layer.clear()
	producer_layer.clear()
	recycler_layer.clear()
	signal_tower_layer.clear()
	_active_signals.clear()
	_last_signal_emit_beat_index = -1
	level_id = ""
	display_name = ""
	grid_width = 0
	grid_height = 0


func apply_level_metadata(level_data: LevelData) -> void:
	level_id = level_data.level_id
	display_name = level_data.display_name
	grid_width = level_data.grid_width
	grid_height = level_data.grid_height


func add_level_content(node: Node) -> void:
	node.add_to_group("runtime_level_content")
	add_child(node)


func _create_layer() -> MapLayer:
	var layer: MapLayer = MapLayer.new()
	layer.cell_size = _config.cell_size
	return layer


func _on_beat_fired(beat_index: int, _beat_time: float) -> void:
	_resolve_producer_spawns(beat_index)
	_resolve_belt_moves(beat_index)
	_resolve_recycler_collection()
	_resolve_signals(beat_index)


func _unhandled_key_input(event: InputEvent) -> void:
	if GM.world != self:
		return

	if not (event is InputEventKey):
		return

	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.keycode != KEY_SPACE and key_event.physical_keycode != KEY_SPACE:
		return

	_emit_signal_towers_for_current_beat()
	get_viewport().set_input_as_handled()


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height


func spawn_cargo(cell: Vector2i, cargo_type: String) -> Cargo:
	if not is_cell_in_bounds(cell):
		return null

	if cargo_layer.has_cell(cell):
		return null

	var cargo: Cargo = CARGO_SCENE.instantiate() as Cargo
	cargo.cargo_type = cargo_type
	cargo.place_at_cell(self, cell)
	add_level_content(cargo)
	return cargo


func _resolve_producer_spawns(beat_index: int) -> void:
	var producer_cells: Dictionary = producer_layer.get_cells()

	for cell in producer_cells.keys():
		var producer: Producer = producer_cells[cell] as Producer
		if producer == null or not is_instance_valid(producer):
			continue

		if not producer.should_trigger_on_beat(beat_index):
			continue

		var target_cell: Vector2i = producer.get_target_cell()
		if not is_cell_in_bounds(target_cell):
			continue

		if cargo_layer.has_cell(target_cell):
			continue

		spawn_cargo(target_cell, producer.cargo_type)


func _resolve_belt_moves(beat_index: int) -> void:
	var belt_cells: Dictionary = belt_layer.get_cells()
	var occupied_cells: Dictionary = cargo_layer.get_cells()
	var requests: Array[Dictionary] = []
	var target_counts: Dictionary = {}

	for cell in belt_cells.keys():
		var belt: Belt = belt_cells[cell] as Belt

		if belt == null or not is_instance_valid(belt):
			continue

		if not belt.should_trigger_on_beat(beat_index):
			continue

		var cargo: Cargo = occupied_cells.get(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		var target_cell: Vector2i = belt.get_target_cell()
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


func _resolve_recycler_collection() -> void:
	var recycler_cells: Dictionary = recycler_layer.get_cells()

	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		if recycler == null or not is_instance_valid(recycler):
			continue

		var cargo: Cargo = cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.remove_from_world()


func _resolve_signals(beat_index: int) -> void:
	for index in range(_active_signals.size() - 1, -1, -1):
		var signal_wave: SignalWave = _active_signals[index] as SignalWave
		if signal_wave == null or not is_instance_valid(signal_wave):
			_active_signals.remove_at(index)
			continue

		signal_wave.advance(beat_index)
		if not signal_wave.is_finished():
			continue

		_active_signals.remove_at(index)
		signal_wave.remove_from_world()


func _emit_signal_towers_for_current_beat() -> void:
	var current_beat_index: int = 0
	if is_instance_valid(_beats):
		current_beat_index = _beats.get_current_beat_index()

	if current_beat_index == _last_signal_emit_beat_index:
		return

	_last_signal_emit_beat_index = current_beat_index

	var signal_tower_cells: Dictionary = signal_tower_layer.get_cells()
	for cell in signal_tower_cells.keys():
		var signal_tower: SignalTower = signal_tower_cells[cell] as SignalTower
		if signal_tower == null or not is_instance_valid(signal_tower):
			continue

		var signal_wave: SignalWave = signal_tower.create_signal_wave(current_beat_index)
		_active_signals.append(signal_wave)
		add_level_content(signal_wave)
