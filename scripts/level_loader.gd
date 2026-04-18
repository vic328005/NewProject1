class_name LevelLoader
extends RefCounted

const BELT_SCENE := preload("res://prefabs/belt.tscn")
const CARGO_SCENE := preload("res://prefabs/cargo.tscn")


func load_level_file_into_world(level_path: String, world: World, beat_conductor: BeatConductor) -> LevelData:
	var level_data: LevelData = LevelData.load_from_file(level_path)
	if level_data == null:
		return null

	if not apply_level_data_to_world(level_data, world, beat_conductor):
		return null

	return level_data


func apply_level_data_to_world(level_data: LevelData, world: World, beat_conductor: BeatConductor) -> bool:
	if level_data == null:
		push_error("Cannot apply a null LevelData instance.")
		return false

	if world == null:
		push_error("Cannot apply level data without a World instance.")
		return false

	if beat_conductor == null:
		push_error("Cannot apply level data without a BeatConductor instance.")
		return false

	world.clear_level_content()
	world.apply_level_metadata(level_data)
	beat_conductor.bpm = level_data.beat_bpm

	for cell_data in level_data.cells:
		var cell: Vector2i = Vector2i(int(cell_data["x"]), int(cell_data["y"]))

		if cell_data.has("belt"):
			var belt_data: Dictionary = Dictionary(cell_data["belt"])
			var belt: Belt = _create_belt(cell, belt_data, world)
			world.add_level_content(belt)

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
	cargo.position = world.cell_to_world(cell)
	cargo.cargo_type = String(cargo_data["type"])
	return cargo


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


func _to_belt_turn_mode(turn_mode_name: String) -> Belt.TurnMode:
	match turn_mode_name:
		"LEFT":
			return Belt.TurnMode.LEFT
		"RIGHT":
			return Belt.TurnMode.RIGHT
		_:
			return Belt.TurnMode.STRAIGHT
