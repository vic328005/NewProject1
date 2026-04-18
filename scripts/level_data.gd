class_name LevelData
extends RefCounted

const TOP_LEVEL_KEYS := [
	"level_id",
	"display_name",
	"grid_width",
	"grid_height",
	"beat_bpm",
	"cells",
	"entities",
]
const CELL_KEYS := ["x", "y", "belt", "cargo"]
const BELT_KEYS := ["facing", "turn_mode", "beat_interval"]
const CARGO_KEYS := ["type"]
const ENTITY_KEYS := ["id", "kind", "x", "y", "data"]
const BELT_FACING_VALUES := ["UP", "RIGHT", "DOWN", "LEFT"]
const BELT_TURN_MODE_VALUES := ["STRAIGHT", "LEFT", "RIGHT"]
const CARGO_TYPE_VALUES := ["NORMAL"]

var level_id: String = ""
var display_name: String = ""
var grid_width: int = 0
var grid_height: int = 0
var beat_bpm: float = 60.0
var cells: Array[Dictionary] = []
var entities: Array[LevelEntityData] = []


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

	if not _has_positive_integer_number(raw_data, "grid_width"):
		return _validation_error(source_label, "grid_width must be an integer greater than 0")

	if not _has_positive_integer_number(raw_data, "grid_height"):
		return _validation_error(source_label, "grid_height must be an integer greater than 0")

	if not raw_data.has("beat_bpm"):
		return _validation_error(source_label, "beat_bpm is required")

	var raw_beat_bpm: Variant = raw_data["beat_bpm"]
	if typeof(raw_beat_bpm) != TYPE_INT and typeof(raw_beat_bpm) != TYPE_FLOAT:
		return _validation_error(source_label, "beat_bpm must be a number")

	var normalized_beat_bpm: float = float(raw_beat_bpm)
	if normalized_beat_bpm <= 0.0:
		return _validation_error(source_label, "beat_bpm must be greater than 0")

	if not raw_data.has("cells") or typeof(raw_data["cells"]) != TYPE_ARRAY:
		return _validation_error(source_label, "cells must be an array")

	if not raw_data.has("entities") or typeof(raw_data["entities"]) != TYPE_ARRAY:
		return _validation_error(source_label, "entities must be an array")

	var level_data: LevelData = LevelData.new()
	level_data.level_id = String(raw_data["level_id"])
	level_data.display_name = String(raw_data["display_name"])
	level_data.grid_width = int(raw_data["grid_width"])
	level_data.grid_height = int(raw_data["grid_height"])
	level_data.beat_bpm = normalized_beat_bpm

	var seen_cells: Dictionary = {}
	var raw_cells: Array = Array(raw_data["cells"])
	for index in range(raw_cells.size()):
		if typeof(raw_cells[index]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "cells[%d] must be an object" % index)

		var normalized_cell: Variant = _parse_cell(raw_cells[index], index, level_data.grid_width, level_data.grid_height, seen_cells, source_label)
		if normalized_cell == null:
			return null

		level_data.cells.append(normalized_cell)

	var seen_entity_ids: Dictionary = {}
	var raw_entities: Array = Array(raw_data["entities"])
	for index in range(raw_entities.size()):
		if typeof(raw_entities[index]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "entities[%d] must be an object" % index)

		var entity_data: LevelEntityData = _parse_entity(raw_entities[index], index, level_data.grid_width, level_data.grid_height, seen_entity_ids, source_label)
		if entity_data == null:
			return null

		level_data.entities.append(entity_data)

	return level_data


static func _parse_cell(raw_cell: Dictionary, index: int, level_width: int, level_height: int, seen_cells: Dictionary, source_label: String) -> Variant:
	var cell_label: String = "cells[%d]" % index
	if not _ensure_allowed_keys(raw_cell, CELL_KEYS, cell_label, source_label):
		return null

	if not _has_integer_number(raw_cell, "x"):
		return _validation_error(source_label, "%s.x must be an integer" % cell_label)

	if not _has_integer_number(raw_cell, "y"):
		return _validation_error(source_label, "%s.y must be an integer" % cell_label)

	var x: int = int(raw_cell["x"])
	var y: int = int(raw_cell["y"])
	if x < 0 or x >= level_width or y < 0 or y >= level_height:
		return _validation_error(source_label, "%s coordinates (%d, %d) are out of bounds" % [cell_label, x, y])

	var cell: Vector2i = Vector2i(x, y)
	if seen_cells.has(cell):
		return _validation_error(source_label, "duplicate cell coordinates found at (%d, %d)" % [x, y])

	var has_belt: bool = raw_cell.has("belt")
	var has_cargo: bool = raw_cell.has("cargo")
	if not has_belt and not has_cargo:
		return _validation_error(source_label, "%s must contain at least one of belt or cargo" % cell_label)

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

	if not BELT_FACING_VALUES.has(facing):
		return _validation_error(source_label, "%s.facing must be one of %s" % [belt_label, BELT_FACING_VALUES])

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

	var cargo_type: String = String(raw_cargo["type"])
	if not CARGO_TYPE_VALUES.has(cargo_type):
		return _validation_error(source_label, "%s.type must be one of %s" % [cargo_label, CARGO_TYPE_VALUES])

	return {
		"type": cargo_type,
	}


static func _parse_entity(raw_entity: Dictionary, index: int, level_width: int, level_height: int, seen_entity_ids: Dictionary, source_label: String) -> LevelEntityData:
	var entity_label: String = "entities[%d]" % index
	if not _ensure_allowed_keys(raw_entity, ENTITY_KEYS, entity_label, source_label):
		return null

	if not _has_non_empty_string(raw_entity, "id"):
		_validation_error(source_label, "%s.id must be a non-empty string" % entity_label)
		return null

	if not _has_non_empty_string(raw_entity, "kind"):
		_validation_error(source_label, "%s.kind must be a non-empty string" % entity_label)
		return null

	if not _has_integer_number(raw_entity, "x"):
		_validation_error(source_label, "%s.x must be an integer" % entity_label)
		return null

	if not _has_integer_number(raw_entity, "y"):
		_validation_error(source_label, "%s.y must be an integer" % entity_label)
		return null

	if not raw_entity.has("data") or typeof(raw_entity["data"]) != TYPE_DICTIONARY:
		_validation_error(source_label, "%s.data must be an object" % entity_label)
		return null

	var entity_id: String = String(raw_entity["id"])
	var kind: String = String(raw_entity["kind"])
	var x: int = int(raw_entity["x"])
	var y: int = int(raw_entity["y"])
	if x < 0 or x >= level_width or y < 0 or y >= level_height:
		_validation_error(source_label, "%s coordinates (%d, %d) are out of bounds" % [entity_label, x, y])
		return null

	if seen_entity_ids.has(entity_id):
		_validation_error(source_label, "duplicate entity id found: %s" % entity_id)
		return null

	if kind != kind.to_upper():
		_validation_error(source_label, "%s.kind must use uppercase naming" % entity_label)
		return null

	var entity: LevelEntityData = LevelEntityData.new()
	entity.id = entity_id
	entity.kind = kind
	entity.cell = Vector2i(x, y)
	entity.data = Dictionary(raw_entity["data"]).duplicate(true)
	seen_entity_ids[entity_id] = true
	return entity


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
