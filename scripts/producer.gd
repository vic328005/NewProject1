extends Machine
class_name Producer

@export var facing: Direction.Value = Direction.Value.RIGHT:
	set(value):
		facing = value

@export_range(1, 16, 1) var beat_interval: int = 2:
	set(value):
		beat_interval = maxi(value, 1)

@export var production_sequence: Array[String] = []:
	set(value):
		production_sequence = _normalize_production_sequence(value)
		_next_production_index = 0

var _next_production_index: int = 0
var _pending_output_cargo_type: String = ""
var _output_ready_beat: int = -1

func should_trigger_on_beat(beat_index: int) -> bool:
	return beat_index > 0 and beat_index % beat_interval == 0


func get_target_cell() -> Vector2i:
	return _registered_cell + Direction.to_vector2i(facing)


func has_remaining_production() -> bool:
	return _next_production_index < production_sequence.size()


func get_next_cargo_type() -> String:
	assert(has_remaining_production(), "Producer has no remaining cargo to produce.")
	return production_sequence[_next_production_index]


func mark_produced() -> void:
	assert(has_remaining_production(), "Producer cannot advance production past the configured sequence.")
	_next_production_index += 1


func output(beat_index: int) -> Dictionary:
	if _pending_output_cargo_type == "" or beat_index < _output_ready_beat:
		return {
			"action": "none",
		}

	return {
		"action": "spawn",
		"target_cell": get_target_cell(),
		"item_type": _pending_output_cargo_type,
		"item_kind": Item.Kind.CARGO,
		"on_success": Callable(self, "_commit_output_success"),
	}


func input(_item: Item, _beat_index: int) -> String:
	return "reject"


func transport(_item: Item, _beat_index: int) -> Dictionary:
	return {
		"action": "block",
	}


func start(beat_index: int) -> void:
	if not should_trigger_on_beat(beat_index):
		return

	if not has_remaining_production():
		return

	if _pending_output_cargo_type != "":
		return

	_pending_output_cargo_type = get_next_cargo_type()
	_output_ready_beat = beat_index + 1
	mark_produced()


func _normalize_production_sequence(value: Array) -> Array[String]:
	var normalized_sequence: Array[String] = []
	for cargo_type in value:
		normalized_sequence.append(CargoType.normalize(cargo_type))

	return normalized_sequence


func _commit_output_success() -> void:
	_pending_output_cargo_type = ""
	_output_ready_beat = -1
