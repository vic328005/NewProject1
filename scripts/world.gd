class_name World
extends Node2D

const CARGO_SCENE: PackedScene = preload("res://prefabs/cargo.tscn")
const ENVIRONMENT_SCENE: PackedScene = preload("res://prefabs/environment.tscn")

var main_layer: MapLayer
var cargo_layer: MapLayer
var belt_layer: MapLayer
var producer_layer: MapLayer
var recycler_layer: MapLayer
var signal_tower_layer: MapLayer
var press_machine_layer: MapLayer
var packer_layer: MapLayer
var environment: Node2D
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
	press_machine_layer = _create_layer()
	packer_layer = _create_layer()
	_init_environment()


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
	press_machine_layer.clear()
	packer_layer.clear()
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


func _init_environment() -> void:
	environment = ENVIRONMENT_SCENE.instantiate() as Node2D
	assert(environment != null, "Environment scene root must be a Node2D.")
	environment.name = "Environment"
	add_child(environment)


func _create_layer() -> MapLayer:
	var layer: MapLayer = MapLayer.new()
	layer.cell_size = _config.cell_size
	return layer


func _on_beat_fired(beat_index: int, _beat_time: float) -> void:
	var triggered_press_machines: Dictionary = _collect_triggered_press_machines()
	var triggered_packers: Dictionary = _collect_triggered_packers()
	_resolve_producer_spawns(beat_index)
	_resolve_transport(beat_index, triggered_press_machines)
	_resolve_packers(beat_index, triggered_packers)
	_resolve_press_machines(beat_index, triggered_press_machines)
	_resolve_recycler_collection()
	_resolve_signals(beat_index)


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


func _resolve_transport(beat_index: int, triggered_press_machines: Dictionary) -> void:
	var direct_requests: Array[Dictionary] = []
	var incoming_press_requests: Array[Dictionary] = []
	var occupied_cells: Dictionary = cargo_layer.get_cells().duplicate()
	_collect_belt_requests(beat_index, occupied_cells, direct_requests, incoming_press_requests)
	_collect_idle_press_machine_requests(beat_index, triggered_press_machines, direct_requests)
	_resolve_simple_move_requests(direct_requests, beat_index, occupied_cells)
	_resolve_incoming_press_requests(incoming_press_requests, beat_index, triggered_press_machines)


func _collect_belt_requests(beat_index: int, occupied_cells: Dictionary, direct_requests: Array[Dictionary], incoming_press_requests: Array[Dictionary]) -> void:
	var belt_cells: Dictionary = belt_layer.get_cells()

	for cell in belt_cells.keys():
		var belt: Belt = belt_cells[cell] as Belt
		if belt == null or not is_instance_valid(belt):
			continue

		if not belt.should_trigger_on_beat(beat_index):
			continue

		var cargo: Cargo = occupied_cells.get(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		if cargo.was_resolved_on_beat(beat_index):
			continue

		var request: Dictionary = {
			"cargo": cargo,
			"target_cell": belt.get_target_cell(),
		}
		var target_cell: Vector2i = request["target_cell"]
		if press_machine_layer.has_cell(target_cell):
			incoming_press_requests.append(request)
			continue

		direct_requests.append(request)


func _collect_idle_press_machine_requests(beat_index: int, triggered_press_machines: Dictionary, direct_requests: Array[Dictionary]) -> void:
	var press_machine_cells: Dictionary = press_machine_layer.get_cells()

	for cell in press_machine_cells.keys():
		var press_machine: PressMachine = press_machine_cells[cell] as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if press_machine.is_pressing():
			continue

		if not press_machine.should_trigger_on_beat(beat_index):
			continue

		if _is_press_machine_triggered(press_machine, triggered_press_machines):
			continue

		var cargo: Cargo = cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		if cargo.was_resolved_on_beat(beat_index):
			continue

		direct_requests.append({
			"cargo": cargo,
			"target_cell": press_machine.get_target_cell(),
		})


func _resolve_simple_move_requests(requests: Array[Dictionary], beat_index: int, occupied_cells: Dictionary) -> void:
	var target_counts: Dictionary = {}
	for request in requests:
		var target_cell: Vector2i = request["target_cell"]
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in requests:
		var cargo: Cargo = request["cargo"] as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.mark_resolved_on_beat(beat_index)

		var target_cell: Vector2i = request["target_cell"]
		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if occupied_cells.has(target_cell):
			continue

		cargo.move_to_cell(target_cell)


func _resolve_incoming_press_requests(incoming_press_requests: Array[Dictionary], beat_index: int, triggered_press_machines: Dictionary) -> void:
	var requests_by_cell: Dictionary = {}
	for request in incoming_press_requests:
		var target_cell: Vector2i = request["target_cell"]
		if not requests_by_cell.has(target_cell):
			requests_by_cell[target_cell] = []

		var requests_at_cell: Array = requests_by_cell[target_cell]
		requests_at_cell.append(request)
		requests_by_cell[target_cell] = requests_at_cell

	for cell in requests_by_cell.keys():
		var press_machine: PressMachine = press_machine_layer.get_cell(cell) as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		var requests_at_cell: Array = requests_by_cell[cell]
		if press_machine.is_pressing():
			for request in requests_at_cell:
				var busy_cargo: Cargo = request["cargo"] as Cargo
				if busy_cargo == null or not is_instance_valid(busy_cargo):
					continue

				busy_cargo.mark_resolved_on_beat(beat_index)
				busy_cargo.remove_from_world()

			continue

		if requests_at_cell.size() != 1:
			for request in requests_at_cell:
				var blocked_cargo: Cargo = request["cargo"] as Cargo
				if blocked_cargo == null or not is_instance_valid(blocked_cargo):
					continue

				blocked_cargo.mark_resolved_on_beat(beat_index)

			continue

		if cargo_layer.has_cell(cell):
			var occupied_cargo: Cargo = requests_at_cell[0]["cargo"] as Cargo
			if occupied_cargo != null and is_instance_valid(occupied_cargo):
				occupied_cargo.mark_resolved_on_beat(beat_index)

			continue

		var request: Dictionary = requests_at_cell[0]
		var cargo: Cargo = request["cargo"] as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.mark_resolved_on_beat(beat_index)

		if _is_press_machine_triggered(press_machine, triggered_press_machines):
			cargo.move_to_cell(cell)
			continue

		cargo.move_to_cell(cell)


func _resolve_press_machines(beat_index: int, triggered_press_machines: Dictionary) -> void:
	_resolve_finished_press_outputs(beat_index)
	_start_triggered_presses(beat_index, triggered_press_machines)


func _resolve_packers(beat_index: int, triggered_packers: Dictionary) -> void:
	var output_requests: Array[Dictionary] = []
	var target_counts: Dictionary = {}

	for cell in triggered_packers.keys():
		var packer_state: Dictionary = triggered_packers[cell]
		var packer: Packer = packer_state.get("packer") as Packer
		var cargo: Cargo = packer_state.get("cargo") as Cargo
		if packer == null or not is_instance_valid(packer):
			continue

		if cargo == null or not is_instance_valid(cargo):
			continue

		if cargo.get_registered_cell() != packer.get_registered_cell():
			continue

		var target_cell: Vector2i = packer.get_target_cell()
		output_requests.append({
			"cargo": cargo,
			"target_cell": target_cell,
		})

		if is_cell_in_bounds(target_cell):
			target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in output_requests:
		var cargo: Cargo = request["cargo"] as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		cargo.is_packaged = true
		cargo.mark_resolved_on_beat(beat_index)

		var target_cell: Vector2i = request["target_cell"]
		if not is_cell_in_bounds(target_cell):
			continue

		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if cargo_layer.has_cell(target_cell):
			continue

		cargo.move_to_cell(target_cell)


func _resolve_finished_press_outputs(beat_index: int) -> void:
	var press_machine_cells: Dictionary = press_machine_layer.get_cells()
	var output_requests: Array[Dictionary] = []
	var target_counts: Dictionary = {}

	for cell in press_machine_cells.keys():
		var press_machine: PressMachine = press_machine_cells[cell] as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if not press_machine.has_finished_press(beat_index):
			continue

		if not press_machine.should_trigger_on_beat(beat_index):
			continue

		var cargo: Cargo = press_machine.get_pressed_cargo()
		if cargo == null or not is_instance_valid(cargo):
			press_machine.clear_pressed_cargo()
			continue

		cargo.cargo_type = press_machine.cargo_type
		var target_cell: Vector2i = press_machine.get_target_cell()
		output_requests.append({
			"cargo": cargo,
			"target_cell": target_cell,
			"press_machine": press_machine,
		})
		target_counts[target_cell] = int(target_counts.get(target_cell, 0)) + 1

	for request in output_requests:
		var press_machine: PressMachine = request["press_machine"] as PressMachine
		var cargo: Cargo = request["cargo"] as Cargo
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if cargo == null or not is_instance_valid(cargo):
			press_machine.clear_pressed_cargo()
			continue

		cargo.mark_resolved_on_beat(beat_index)

		var target_cell: Vector2i = request["target_cell"]
		if int(target_counts.get(target_cell, 0)) != 1:
			continue

		if cargo_layer.has_cell(target_cell):
			continue

		if not cargo.move_to_cell(target_cell):
			continue

		press_machine.clear_pressed_cargo()


func _start_triggered_presses(beat_index: int, triggered_press_machines: Dictionary) -> void:
	for cell in triggered_press_machines.keys():
		var press_machine: PressMachine = triggered_press_machines[cell] as PressMachine
		if press_machine == null or not is_instance_valid(press_machine):
			continue

		if press_machine.is_pressing():
			continue

		var cargo: Cargo = cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		press_machine.begin_press(cargo, beat_index)
		cargo.mark_resolved_on_beat(beat_index)


func _collect_triggered_press_machines() -> Dictionary:
	var triggered_press_machines: Dictionary = {}

	for signal_wave_node in _active_signals:
		var signal_wave: SignalWave = signal_wave_node as SignalWave
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var press_machine: PressMachine = press_machine_layer.get_cell(cell) as PressMachine
			if press_machine == null or not is_instance_valid(press_machine):
				continue

			triggered_press_machines[cell] = press_machine

	return triggered_press_machines


func _collect_triggered_packers() -> Dictionary:
	var triggered_packers: Dictionary = {}

	for signal_wave_node in _active_signals:
		var signal_wave: SignalWave = signal_wave_node as SignalWave
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var packer: Packer = packer_layer.get_cell(cell) as Packer
			if packer == null or not is_instance_valid(packer):
				continue

			# 这里记录信号命中当下的货物快照，避免同拍后续运输把新货送进来后被误打包。
			triggered_packers[cell] = {
				"packer": packer,
				"cargo": cargo_layer.get_cell(cell) as Cargo,
			}

	return triggered_packers


func _is_press_machine_triggered(press_machine: PressMachine, triggered_press_machines: Dictionary) -> bool:
	if press_machine == null or not is_instance_valid(press_machine):
		return false

	return triggered_press_machines.has(press_machine.get_registered_cell())


func _resolve_recycler_collection() -> void:
	var recycler_cells: Dictionary = recycler_layer.get_cells()

	for cell in recycler_cells.keys():
		var recycler: Recycler = recycler_cells[cell] as Recycler
		if recycler == null or not is_instance_valid(recycler):
			continue

		var cargo: Cargo = cargo_layer.get_cell(cell) as Cargo
		if cargo == null or not is_instance_valid(cargo):
			continue

		GM.register_recycled_cargo(cargo.cargo_type)
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


func try_emit_signal_towers_for_current_beat() -> bool:
	var current_beat_index: int = 0
	if is_instance_valid(_beats):
		current_beat_index = _beats.get_current_beat_index()

	if current_beat_index == _last_signal_emit_beat_index:
		return false

	var emitted: bool = false
	var signal_tower_cells: Dictionary = signal_tower_layer.get_cells()
	for cell in signal_tower_cells.keys():
		var signal_tower: SignalTower = signal_tower_cells[cell] as SignalTower
		if signal_tower == null or not is_instance_valid(signal_tower):
			continue

		var signal_wave: SignalWave = signal_tower.create_signal_wave(current_beat_index)
		_active_signals.append(signal_wave)
		add_level_content(signal_wave)
		emitted = true

	if not emitted:
		return false

	_last_signal_emit_beat_index = current_beat_index
	return true
