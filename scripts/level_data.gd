class_name LevelData
extends RefCounted

const TOP_LEVEL_KEYS := [
	"level_id",
	"display_name",
	"beat_bpm",
	"cells",
]
const CELL_KEYS := ["x", "y", "belt", "cargo", "producer", "recycler", "signal_tower", "press_machine", "packer"]
const BELT_KEYS := ["facing", "turn_mode", "beat_interval"]
const CARGO_KEYS := ["type"]
const PRODUCER_KEYS := ["facing", "beat_interval", "production_sequence"]
const RECYCLER_KEYS := ["targets"]
const RECYCLER_TARGET_KEYS := ["product_type", "required_count"]
const SIGNAL_TOWER_KEYS: Array = ["max_steps"]
const PRESS_MACHINE_KEYS := ["facing", "cargo_type", "beat_interval"]
const PACKER_KEYS := ["facing"]
const BELT_TURN_MODE_VALUES := ["STRAIGHT", "LEFT", "RIGHT"]
const CARGO_TYPE_VALUES: Array[String] = CargoType.VALUES

var level_id: String = ""
var display_name: String = ""
var beat_bpm: float = 60.0
var cells: Array[Dictionary] = []


static func load_from_file(path: String) -> LevelData:
	if not FileAccess.file_exists(path):
		push_error("Level file does not exist: %s" % path)
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open level file: %s" % path)
		return null

	return from_json_text(file.get_as_text(), path)


static func from_json_text(json_text: String, source_label: String = "<memory>") -> LevelData:
	var json: JSON = JSON.new()
	var parse_error: int = json.parse(json_text)
	if parse_error != OK:
		push_error(
			"Failed to parse level JSON %s: %s at line %d" % [
				source_label,
				json.get_error_message(),
				json.get_error_line(),
			]
		)
		return null

	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("Level root must be a JSON object: %s" % source_label)
		return null

	var raw_data: Dictionary = json.data
	return from_dictionary(raw_data, source_label)


static func from_dictionary(raw_data: Dictionary, source_label: String = "<memory>") -> LevelData:
	if not _ensure_allowed_keys(raw_data, TOP_LEVEL_KEYS, "root", source_label):
		return null

	if not _has_non_empty_string(raw_data, "level_id"):
		return _validation_error(source_label, "level_id must be a non-empty string")

	if not _has_non_empty_string(raw_data, "display_name"):
		return _validation_error(source_label, "display_name must be a non-empty string")

	if not raw_data.has("cells") or typeof(raw_data["cells"]) != TYPE_ARRAY:
		return _validation_error(source_label, "cells must be an array")

	var level_data: LevelData = LevelData.new()
	level_data.level_id = String(raw_data["level_id"])
	level_data.display_name = String(raw_data["display_name"])
	if raw_data.has("beat_bpm"):
		var raw_beat_bpm: Variant = raw_data["beat_bpm"]
		if typeof(raw_beat_bpm) != TYPE_INT and typeof(raw_beat_bpm) != TYPE_FLOAT:
			return _validation_error(source_label, "beat_bpm must be a number")

		var normalized_beat_bpm: float = float(raw_beat_bpm)
		if normalized_beat_bpm <= 0.0:
			return _validation_error(source_label, "beat_bpm must be greater than 0")

		level_data.beat_bpm = normalized_beat_bpm

	var seen_cells: Dictionary = {}
	var raw_cells: Array = Array(raw_data["cells"])
	for index in range(raw_cells.size()):
		if typeof(raw_cells[index]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "cells[%d] must be an object" % index)

		var normalized_cell: Variant = _parse_cell(raw_cells[index], index, seen_cells, source_label)
		if normalized_cell == null:
			return null

		level_data.cells.append(normalized_cell)

	return level_data


static func _parse_cell(raw_cell: Dictionary, index: int, seen_cells: Dictionary, source_label: String) -> Variant:
	var cell_label: String = "cells[%d]" % index
	if not _ensure_allowed_keys(raw_cell, CELL_KEYS, cell_label, source_label):
		return null

	if not _has_integer_number(raw_cell, "x"):
		return _validation_error(source_label, "%s.x must be an integer" % cell_label)

	if not _has_integer_number(raw_cell, "y"):
		return _validation_error(source_label, "%s.y must be an integer" % cell_label)

	var x: int = int(raw_cell["x"])
	var y: int = int(raw_cell["y"])
	var cell: Vector2i = Vector2i(x, y)
	if seen_cells.has(cell):
		return _validation_error(source_label, "duplicate cell coordinates found at (%d, %d)" % [x, y])

	var has_belt: bool = raw_cell.has("belt")
	var has_cargo: bool = raw_cell.has("cargo")
	var has_producer: bool = raw_cell.has("producer")
	var has_recycler: bool = raw_cell.has("recycler")
	var has_signal_tower: bool = raw_cell.has("signal_tower")
	var has_press_machine: bool = raw_cell.has("press_machine")
	var has_packer: bool = raw_cell.has("packer")
	if not has_belt and not has_cargo and not has_producer and not has_recycler and not has_signal_tower and not has_press_machine and not has_packer:
		return _validation_error(source_label, "%s must contain at least one gameplay object" % cell_label)

	if has_signal_tower and (has_belt or has_cargo or has_producer or has_recycler or has_press_machine or has_packer):
		return _validation_error(source_label, "%s.signal_tower must occupy its own cell" % cell_label)

	if has_press_machine and (has_belt or has_producer or has_recycler or has_signal_tower or has_packer):
		return _validation_error(source_label, "%s.press_machine can only share a cell with cargo" % cell_label)

	if has_packer and (has_belt or has_producer or has_recycler or has_signal_tower or has_press_machine):
		return _validation_error(source_label, "%s.packer can only share a cell with cargo" % cell_label)

	var normalized_cell: Dictionary = {
		"x": x,
		"y": y,
	}

	if has_belt:
		if typeof(raw_cell["belt"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.belt must be an object" % cell_label)

		var normalized_belt: Variant = _parse_belt(raw_cell["belt"], cell_label, source_label)
		if normalized_belt == null:
			return null

		normalized_cell["belt"] = normalized_belt

	if has_cargo:
		if typeof(raw_cell["cargo"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.cargo must be an object" % cell_label)

		var normalized_cargo: Variant = _parse_cargo(raw_cell["cargo"], cell_label, source_label)
		if normalized_cargo == null:
			return null

		normalized_cell["cargo"] = normalized_cargo

	if has_producer:
		if typeof(raw_cell["producer"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.producer must be an object" % cell_label)

		var normalized_producer: Variant = _parse_producer(raw_cell["producer"], cell_label, source_label)
		if normalized_producer == null:
			return null

		normalized_cell["producer"] = normalized_producer

	if has_recycler:
		if typeof(raw_cell["recycler"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.recycler must be an object" % cell_label)

		var normalized_recycler: Variant = _parse_recycler(raw_cell["recycler"], cell_label, source_label)
		if normalized_recycler == null:
			return null

		normalized_cell["recycler"] = normalized_recycler

	if has_signal_tower:
		if typeof(raw_cell["signal_tower"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.signal_tower must be an object" % cell_label)

		var normalized_signal_tower: Variant = _parse_signal_tower(raw_cell["signal_tower"], cell_label, source_label)
		if normalized_signal_tower == null:
			return null

		normalized_cell["signal_tower"] = normalized_signal_tower

	if has_press_machine:
		if typeof(raw_cell["press_machine"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.press_machine must be an object" % cell_label)

		var normalized_press_machine: Variant = _parse_press_machine(raw_cell["press_machine"], cell_label, source_label)
		if normalized_press_machine == null:
			return null

		normalized_cell["press_machine"] = normalized_press_machine

	if has_packer:
		if typeof(raw_cell["packer"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.packer must be an object" % cell_label)

		var normalized_packer: Variant = _parse_packer(raw_cell["packer"], cell_label, source_label)
		if normalized_packer == null:
			return null

		normalized_cell["packer"] = normalized_packer

	seen_cells[cell] = true
	return normalized_cell


static func _parse_belt(raw_belt: Dictionary, cell_label: String, source_label: String) -> Variant:
	var belt_label: String = "%s.belt" % cell_label
	if not _ensure_allowed_keys(raw_belt, BELT_KEYS, belt_label, source_label):
		return null

	if not _has_non_empty_string(raw_belt, "facing"):
		return _validation_error(source_label, "%s.facing must be a non-empty string" % belt_label)

	if not _has_non_empty_string(raw_belt, "turn_mode"):
		return _validation_error(source_label, "%s.turn_mode must be a non-empty string" % belt_label)

	if not _has_positive_integer_number(raw_belt, "beat_interval"):
		return _validation_error(source_label, "%s.beat_interval must be a positive integer" % belt_label)

	var facing: String = String(raw_belt["facing"])
	var turn_mode: String = String(raw_belt["turn_mode"])
	var beat_interval: int = int(raw_belt["beat_interval"])

	if not Direction.is_valid_name(facing):
		return _validation_error(source_label, "%s.facing must be one of %s" % [belt_label, Direction.NAMES])

	if not BELT_TURN_MODE_VALUES.has(turn_mode):
		return _validation_error(source_label, "%s.turn_mode must be one of %s" % [belt_label, BELT_TURN_MODE_VALUES])

	if beat_interval != 1 and beat_interval != 2:
		return _validation_error(source_label, "%s.beat_interval must be 1 or 2" % belt_label)

	return {
		"facing": facing,
		"turn_mode": turn_mode,
		"beat_interval": beat_interval,
	}


static func _parse_cargo(raw_cargo: Dictionary, cell_label: String, source_label: String) -> Variant:
	var cargo_label: String = "%s.cargo" % cell_label
	if not _ensure_allowed_keys(raw_cargo, CARGO_KEYS, cargo_label, source_label):
		return null

	if not _has_non_empty_string(raw_cargo, "type"):
		return _validation_error(source_label, "%s.type must be a non-empty string" % cargo_label)

	var cargo_type: String = CargoType.normalize(raw_cargo["type"])
	if not CargoType.is_valid(cargo_type):
		return _validation_error(source_label, "%s.type must be one of %s" % [cargo_label, CARGO_TYPE_VALUES])

	return {
		"type": cargo_type,
	}


static func _parse_producer(raw_producer: Dictionary, cell_label: String, source_label: String) -> Variant:
	var producer_label: String = "%s.producer" % cell_label
	if not _ensure_allowed_keys(raw_producer, PRODUCER_KEYS, producer_label, source_label):
		return null

	if not _has_non_empty_string(raw_producer, "facing"):
		return _validation_error(source_label, "%s.facing must be a non-empty string" % producer_label)

	if not _has_positive_integer_number(raw_producer, "beat_interval"):
		return _validation_error(source_label, "%s.beat_interval must be a positive integer" % producer_label)

	if not raw_producer.has("production_sequence") or typeof(raw_producer["production_sequence"]) != TYPE_ARRAY:
		return _validation_error(source_label, "%s.production_sequence must be an array" % producer_label)

	var facing: String = String(raw_producer["facing"]).strip_edges().to_upper()
	var beat_interval: int = int(raw_producer["beat_interval"])
	var normalized_sequence: Array[String] = []
	var raw_sequence: Array = Array(raw_producer["production_sequence"])

	if not Direction.is_valid_name(facing):
		return _validation_error(source_label, "%s.facing must be one of %s" % [producer_label, Direction.NAMES])

	for index in range(raw_sequence.size()):
		if typeof(raw_sequence[index]) != TYPE_STRING:
			return _validation_error(source_label, "%s.production_sequence[%d] must be a string" % [producer_label, index])

		var cargo_type: String = CargoType.normalize(raw_sequence[index])
		if not CargoType.is_valid(cargo_type):
			return _validation_error(source_label, "%s.production_sequence[%d] must be one of %s" % [producer_label, index, CARGO_TYPE_VALUES])

		normalized_sequence.append(cargo_type)

	return {
		"facing": facing,
		"beat_interval": beat_interval,
		"production_sequence": normalized_sequence,
	}


static func _parse_recycler(raw_recycler: Dictionary, cell_label: String, source_label: String) -> Variant:
	var recycler_label: String = "%s.recycler" % cell_label
	if not _ensure_allowed_keys(raw_recycler, RECYCLER_KEYS, recycler_label, source_label):
		return null

	if not raw_recycler.has("targets") or typeof(raw_recycler["targets"]) != TYPE_ARRAY:
		return _validation_error(source_label, "%s.targets must be an array" % recycler_label)

	var raw_targets: Array = Array(raw_recycler["targets"])
	if raw_targets.is_empty():
		return _validation_error(source_label, "%s.targets must contain at least one target" % recycler_label)

	var normalized_targets: Array[Dictionary] = []
	var seen_product_types: Dictionary = {}
	for index in range(raw_targets.size()):
		if typeof(raw_targets[index]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.targets[%d] must be an object" % [recycler_label, index])

		var normalized_target: Variant = _parse_recycler_target(raw_targets[index], recycler_label, index, source_label)
		if normalized_target == null:
			return null

		var product_type: String = String(normalized_target["product_type"])
		if seen_product_types.has(product_type):
			return _validation_error(source_label, "%s.targets[%d].product_type duplicates %s" % [recycler_label, index, product_type])

		seen_product_types[product_type] = true
		normalized_targets.append(normalized_target)

	return {
		"targets": normalized_targets,
	}


static func _parse_recycler_target(raw_target: Dictionary, recycler_label: String, index: int, source_label: String) -> Variant:
	var target_label: String = "%s.targets[%d]" % [recycler_label, index]
	if not _ensure_allowed_keys(raw_target, RECYCLER_TARGET_KEYS, target_label, source_label):
		return null

	if not _has_non_empty_string(raw_target, "product_type"):
		return _validation_error(source_label, "%s.product_type must be a non-empty string" % target_label)

	if not _has_positive_integer_number(raw_target, "required_count"):
		return _validation_error(source_label, "%s.required_count must be a positive integer" % target_label)

	var product_type: String = CargoType.normalize(raw_target["product_type"])
	if not CargoType.is_valid(product_type):
		return _validation_error(source_label, "%s.product_type must be one of %s" % [target_label, CARGO_TYPE_VALUES])

	return {
		"product_type": product_type,
		"required_count": int(raw_target["required_count"]),
	}


static func _parse_signal_tower(raw_signal_tower: Dictionary, cell_label: String, source_label: String) -> Variant:
	var signal_tower_label: String = "%s.signal_tower" % cell_label
	if not _ensure_allowed_keys(raw_signal_tower, SIGNAL_TOWER_KEYS, signal_tower_label, source_label):
		return null

	var normalized_signal_tower: Dictionary = {}
	if raw_signal_tower.has("max_steps"):
		if not _has_positive_integer_number(raw_signal_tower, "max_steps"):
			return _validation_error(source_label, "%s.max_steps must be a positive integer" % signal_tower_label)

		normalized_signal_tower["max_steps"] = int(raw_signal_tower["max_steps"])

	return normalized_signal_tower


static func _parse_press_machine(raw_press_machine: Dictionary, cell_label: String, source_label: String) -> Variant:
	var press_machine_label: String = "%s.press_machine" % cell_label
	if not _ensure_allowed_keys(raw_press_machine, PRESS_MACHINE_KEYS, press_machine_label, source_label):
		return null

	if not _has_non_empty_string(raw_press_machine, "facing"):
		return _validation_error(source_label, "%s.facing must be a non-empty string" % press_machine_label)

	if not _has_non_empty_string(raw_press_machine, "cargo_type"):
		return _validation_error(source_label, "%s.cargo_type must be a non-empty string" % press_machine_label)

	if not _has_positive_integer_number(raw_press_machine, "beat_interval"):
		return _validation_error(source_label, "%s.beat_interval must be a positive integer" % press_machine_label)

	var facing: String = String(raw_press_machine["facing"]).strip_edges().to_upper()
	var cargo_type: String = CargoType.normalize(raw_press_machine["cargo_type"])
	var beat_interval: int = int(raw_press_machine["beat_interval"])

	if not Direction.is_valid_name(facing):
		return _validation_error(source_label, "%s.facing must be one of %s" % [press_machine_label, Direction.NAMES])

	if not CargoType.is_valid(cargo_type):
		return _validation_error(source_label, "%s.cargo_type must be one of %s" % [press_machine_label, CARGO_TYPE_VALUES])

	if beat_interval != 1 and beat_interval != 2:
		return _validation_error(source_label, "%s.beat_interval must be 1 or 2" % press_machine_label)

	return {
		"facing": facing,
		"cargo_type": cargo_type,
		"beat_interval": beat_interval,
	}


static func _parse_packer(raw_packer: Dictionary, cell_label: String, source_label: String) -> Variant:
	var packer_label: String = "%s.packer" % cell_label
	if not _ensure_allowed_keys(raw_packer, PACKER_KEYS, packer_label, source_label):
		return null

	if not _has_non_empty_string(raw_packer, "facing"):
		return _validation_error(source_label, "%s.facing must be a non-empty string" % packer_label)

	var facing: String = String(raw_packer["facing"]).strip_edges().to_upper()
	if not Direction.is_valid_name(facing):
		return _validation_error(source_label, "%s.facing must be one of %s" % [packer_label, Direction.NAMES])

	return {
		"facing": facing,
	}


static func _ensure_allowed_keys(raw_data: Dictionary, allowed_keys: Array, label: String, source_label: String) -> bool:
	for key in raw_data.keys():
		if typeof(key) != TYPE_STRING:
			push_error("Invalid non-string key in %s of %s" % [label, source_label])
			return false

		if not allowed_keys.has(key):
			push_error("Unexpected field '%s' in %s of %s" % [key, label, source_label])
			return false

	return true


static func _has_non_empty_string(raw_data: Dictionary, key: String) -> bool:
	return raw_data.has(key) and typeof(raw_data[key]) == TYPE_STRING and not String(raw_data[key]).strip_edges().is_empty()


static func _has_int(raw_data: Dictionary, key: String) -> bool:
	return raw_data.has(key) and typeof(raw_data[key]) == TYPE_INT


static func _has_integer_number(raw_data: Dictionary, key: String) -> bool:
	if not raw_data.has(key):
		return false

	var value: Variant = raw_data[key]
	if typeof(value) == TYPE_INT:
		return true

	if typeof(value) != TYPE_FLOAT:
		return false

	var float_value: float = float(value)
	return is_equal_approx(float_value, round(float_value))


static func _has_positive_integer_number(raw_data: Dictionary, key: String) -> bool:
	return _has_integer_number(raw_data, key) and int(raw_data[key]) > 0


static func _validation_error(source_label: String, message: String) -> LevelData:
	push_error("Invalid level data in %s: %s" % [source_label, message])
	return null
