extends Machine
class_name Producer

var facing: Direction.Value = Direction.Value.RIGHT:
	set(value):
		facing = value

var beat_interval: int = 2:
	set(value):
		beat_interval = maxi(value, 1)

var production_sequence: Array[String] = []:
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


func plan_output(beat_index: int, _receives_signal: bool) -> Dictionary:
	if _pending_output_cargo_type == "" or beat_index < _output_ready_beat:
		return {
			"action": "none",
		}

	return {
		"action": "spawn",
		"target_cell": get_target_cell(),
		"item_type": _pending_output_cargo_type,
		"item_kind": Item.Kind.CARGO,
		"flow_direction": facing,
	}


func plan_transport(_item: Item, _beat_index: int, _receives_signal: bool) -> Dictionary:
	return {
		"action": "block",
	}


func plan_input(_item: Item, _beat_index: int, _receives_signal: bool) -> Dictionary:
	return {
		"action": "reject",
	}


func _normalize_production_sequence(value: Array) -> Array[String]:
	var normalized_sequence: Array[String] = []
	for cargo_type in value:
		normalized_sequence.append(CargoType.normalize(cargo_type))

	return normalized_sequence
