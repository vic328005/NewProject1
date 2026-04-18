class_name LevelLoader
extends RefCounted

const BELT_SCENE := preload("res://prefabs/belt.tscn")
const CARGO_SCENE := preload("res://prefabs/cargo.tscn")
const PRODUCER_SCENE := preload("res://prefabs/producer.tscn")
const RECYCLER_SCENE := preload("res://prefabs/recycler.tscn")
const SIGNAL_TOWER_SCENE: PackedScene = preload("res://prefabs/signal_tower.tscn")


func load_level_file_into_world(level_path: String, world: World, beats: BeatConductor) -> LevelData:
	var level_data: LevelData = LevelData.load_from_file(level_path)
	if level_data == null:
		return null

	if not apply_level_data_to_world(level_data, world, beats):
		return null

	return level_data


func apply_level_data_to_world(level_data: LevelData, world: World, beats: BeatConductor) -> bool:
	if level_data == null:
		push_error("Cannot apply a null LevelData instance.")
		return false

	if world == null:
		push_error("Cannot apply level data without a World instance.")
		return false

	if beats == null:
		push_error("Cannot apply level data without a BeatConductor instance.")
		return false

	world.clear_level_content()
	world.apply_level_metadata(level_data)
	beats.bpm = level_data.beat_bpm

	for cell_data in level_data.cells:
		var cell: Vector2i = Vector2i(int(cell_data["x"]), int(cell_data["y"]))

		if cell_data.has("belt"):
			var belt_data: Dictionary = Dictionary(cell_data["belt"])
			var belt: Belt = _create_belt(cell, belt_data, world)
			world.add_level_content(belt)

		if cell_data.has("producer"):
			var producer_data: Dictionary = Dictionary(cell_data["producer"])
			var producer: Producer = _create_producer(cell, producer_data, world)
			world.add_level_content(producer)

		if cell_data.has("recycler"):
			var recycler_data: Dictionary = Dictionary(cell_data["recycler"])
			var recycler: Recycler = _create_recycler(cell, recycler_data, world)
			world.add_level_content(recycler)

		if cell_data.has("signal_tower"):
			var signal_tower_data: Dictionary = Dictionary(cell_data["signal_tower"])
			var signal_tower: SignalTower = _create_signal_tower(cell, signal_tower_data, world)
			world.add_level_content(signal_tower)

		if cell_data.has("cargo"):
			var cargo_data: Dictionary = Dictionary(cell_data["cargo"])
			var cargo: Cargo = _create_cargo(cell, cargo_data, world)
			world.add_level_content(cargo)

	return true


func _create_belt(cell: Vector2i, belt_data: Dictionary, world: World) -> Belt:
	var belt: Belt = BELT_SCENE.instantiate() as Belt
	belt.position = world.cell_to_world(cell)
	belt.facing = _to_belt_direction(String(belt_data["facing"]))
	belt.turn_mode = _to_belt_turn_mode(String(belt_data["turn_mode"]))
	belt.beat_interval = int(belt_data["beat_interval"])
	return belt


func _create_cargo(cell: Vector2i, cargo_data: Dictionary, world: World) -> Cargo:
	var cargo: Cargo = CARGO_SCENE.instantiate() as Cargo
	cargo.cargo_type = String(cargo_data["type"])
	cargo.place_at_cell(world, cell)
	return cargo


func _create_producer(cell: Vector2i, producer_data: Dictionary, world: World) -> Producer:
	var producer: Producer = PRODUCER_SCENE.instantiate() as Producer
	producer.position = world.cell_to_world(cell)
	producer.facing = _to_producer_direction(String(producer_data["facing"]))
	producer.beat_interval = int(producer_data["beat_interval"])
	producer.cargo_type = String(producer_data["cargo_type"])
	return producer


func _create_recycler(cell: Vector2i, _recycler_data: Dictionary, world: World) -> Recycler:
	var recycler: Recycler = RECYCLER_SCENE.instantiate() as Recycler
	recycler.position = world.cell_to_world(cell)
	return recycler


func _create_signal_tower(cell: Vector2i, signal_tower_data: Dictionary, world: World) -> SignalTower:
	var signal_tower: SignalTower = SIGNAL_TOWER_SCENE.instantiate() as SignalTower
	signal_tower.position = world.cell_to_world(cell)
	if signal_tower_data.has("max_steps"):
		signal_tower.max_steps = int(signal_tower_data["max_steps"])
	return signal_tower


func _to_belt_direction(direction_name: String) -> Belt.Direction:
	match direction_name:
		"UP":
			return Belt.Direction.UP
		"RIGHT":
			return Belt.Direction.RIGHT
		"DOWN":
			return Belt.Direction.DOWN
		_:
			return Belt.Direction.LEFT


func _to_producer_direction(direction_name: String) -> Producer.Direction:
	match direction_name:
		"UP":
			return Producer.Direction.UP
		"RIGHT":
			return Producer.Direction.RIGHT
		"DOWN":
			return Producer.Direction.DOWN
		_:
			return Producer.Direction.LEFT


func _to_belt_turn_mode(turn_mode_name: String) -> Belt.TurnMode:
	match turn_mode_name:
		"LEFT":
			return Belt.TurnMode.LEFT
		"RIGHT":
			return Belt.TurnMode.RIGHT
		_:
			return Belt.TurnMode.STRAIGHT
