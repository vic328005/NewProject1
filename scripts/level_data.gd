class_name LevelData
extends RefCounted

const TOP_LEVEL_KEYS := [
	"level_id",
	"display_name",
	"beat_bpm",
	"failure_beat_limit",
	"cells",
]
const CELL_KEYS := ["x", "y", "belt", "item", "producer", "recycler", "signal_tower", "press_machine", "packer"]
const BELT_KEYS := ["input_direction", "output_direction", "beat_interval"]
const ITEM_KEYS := ["kind", "type"]
const PRODUCER_KEYS := ["facing", "beat_interval", "production_sequence"]
const RECYCLER_KEYS := ["targets"]
const RECYCLER_TARGET_KEYS := ["product_type", "required_count"]
const SIGNAL_TOWER_KEYS: Array = ["max_steps"]
const PRESS_MACHINE_KEYS := ["facing", "cargo_type", "beat_interval", "transport_beat_interval"]
const PACKER_KEYS := ["facing", "transport_beat_interval"]
const CARGO_TYPE_VALUES: Array[String] = CargoType.VALUES
const ITEM_KIND_VALUES := ["CARGO", "PRODUCT"]
const DEFAULT_FAILURE_BEAT_LIMIT: int = 60
static var _last_error_message: String = ""

var level_id: String = ""
var display_name: String = ""
var beat_bpm: float = 160.0
var failure_beat_limit: int = DEFAULT_FAILURE_BEAT_LIMIT
var cells: Array[Dictionary] = []


static func clear_last_error_message() -> void:
	_last_error_message = ""


static func get_last_error_message() -> String:
	return _last_error_message


static func load_from_file(path: String) -> LevelData:
	clear_last_error_message()
	if not FileAccess.file_exists(path):
		_report_error("找不到关卡文件：%s" % path)
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_report_error("无法打开关卡文件：%s" % path)
		return null

	return from_json_text(file.get_as_text(), path)


static func from_json_text(json_text: String, source_label: String = "<memory>") -> LevelData:
	clear_last_error_message()
	var json: JSON = JSON.new()
	var parse_error: int = json.parse(json_text)
	if parse_error != OK:
		var error_message: String = "JSON 解析失败：第 %d 行附近存在语法错误" % json.get_error_line()
		_set_last_error_message(error_message)
		push_error("%s（文件：%s，原始错误：%s）" % [error_message, source_label, json.get_error_message()])
		return null

	if typeof(json.data) != TYPE_DICTIONARY:
		_report_error("关卡 JSON 顶层必须是对象", source_label)
		return null

	var raw_data: Dictionary = json.data
	return from_dictionary(raw_data, source_label)


static func from_dictionary(raw_data: Dictionary, source_label: String = "<memory>") -> LevelData:
	clear_last_error_message()
	if not _ensure_allowed_keys(raw_data, TOP_LEVEL_KEYS, "顶层", source_label):
		return null

	if not _has_non_empty_string(raw_data, "level_id"):
		return _validation_error(source_label, "level_id 必须是非空字符串")

	if not _has_non_empty_string(raw_data, "display_name"):
		return _validation_error(source_label, "display_name 必须是非空字符串")

	if not raw_data.has("cells") or typeof(raw_data["cells"]) != TYPE_ARRAY:
		return _validation_error(source_label, "cells 必须是数组")

	var level_data: LevelData = LevelData.new()
	level_data.level_id = String(raw_data["level_id"])
	level_data.display_name = String(raw_data["display_name"])
	if raw_data.has("beat_bpm"):
		var raw_beat_bpm: Variant = raw_data["beat_bpm"]
		if typeof(raw_beat_bpm) != TYPE_INT and typeof(raw_beat_bpm) != TYPE_FLOAT:
			return _validation_error(source_label, "beat_bpm 必须是数字")

		var normalized_beat_bpm: float = float(raw_beat_bpm)
		if normalized_beat_bpm <= 0.0:
			return _validation_error(source_label, "beat_bpm 必须大于 0")

		level_data.beat_bpm = normalized_beat_bpm

	if raw_data.has("failure_beat_limit"):
		if not _has_positive_integer_number(raw_data, "failure_beat_limit"):
			return _validation_error(source_label, "failure_beat_limit 必须是正整数")

		level_data.failure_beat_limit = int(raw_data["failure_beat_limit"])

	var seen_cells: Dictionary = {}
	var raw_cells: Array = Array(raw_data["cells"])
	for index in range(raw_cells.size()):
		if typeof(raw_cells[index]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "cells[%d] 必须是对象" % index)

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
		return _validation_error(source_label, "%s.x 必须是整数" % cell_label)

	if not _has_integer_number(raw_cell, "y"):
		return _validation_error(source_label, "%s.y 必须是整数" % cell_label)

	var x: int = int(raw_cell["x"])
	var y: int = int(raw_cell["y"])
	var cell: Vector2i = Vector2i(x, y)
	if seen_cells.has(cell):
		return _validation_error(source_label, "发现重复的格子坐标 (%d, %d)" % [x, y])

	var has_belt: bool = raw_cell.has("belt")
	var has_item: bool = raw_cell.has("item")
	var has_producer: bool = raw_cell.has("producer")
	var has_recycler: bool = raw_cell.has("recycler")
	var has_signal_tower: bool = raw_cell.has("signal_tower")
	var has_press_machine: bool = raw_cell.has("press_machine")
	var has_packer: bool = raw_cell.has("packer")
	var machine_count: int = 0
	if has_belt:
		machine_count += 1
	if has_producer:
		machine_count += 1
	if has_recycler:
		machine_count += 1
	if has_press_machine:
		machine_count += 1
	if has_packer:
		machine_count += 1
	if not has_belt and not has_item and not has_producer and not has_recycler and not has_signal_tower and not has_press_machine and not has_packer:
		return _validation_error(source_label, "%s 至少需要包含一个玩法对象" % cell_label)

	if has_signal_tower and (has_belt or has_item or has_producer or has_recycler or has_press_machine or has_packer):
		return _validation_error(source_label, "%s.signal_tower 必须独占一个格子" % cell_label)

	if machine_count > 1:
		return _validation_error(source_label, "%s 最多只能包含一个机器" % cell_label)

	var normalized_cell: Dictionary = {
		"x": x,
		"y": y,
	}

	if has_belt:
		if typeof(raw_cell["belt"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.belt 必须是对象" % cell_label)

		var normalized_belt: Variant = _parse_belt(raw_cell["belt"], cell_label, source_label)
		if normalized_belt == null:
			return null

		normalized_cell["belt"] = normalized_belt

	if has_item:
		if typeof(raw_cell["item"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.item 必须是对象" % cell_label)

		var normalized_item: Variant = _parse_item(raw_cell["item"], cell_label, source_label)
		if normalized_item == null:
			return null

		normalized_cell["item"] = normalized_item

	if has_producer:
		if typeof(raw_cell["producer"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.producer 必须是对象" % cell_label)

		var normalized_producer: Variant = _parse_producer(raw_cell["producer"], cell_label, source_label)
		if normalized_producer == null:
			return null

		normalized_cell["producer"] = normalized_producer

	if has_recycler:
		if typeof(raw_cell["recycler"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.recycler 必须是对象" % cell_label)

		var normalized_recycler: Variant = _parse_recycler(raw_cell["recycler"], cell_label, source_label)
		if normalized_recycler == null:
			return null

		normalized_cell["recycler"] = normalized_recycler

	if has_signal_tower:
		if typeof(raw_cell["signal_tower"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.signal_tower 必须是对象" % cell_label)

		var normalized_signal_tower: Variant = _parse_signal_tower(raw_cell["signal_tower"], cell_label, source_label)
		if normalized_signal_tower == null:
			return null

		normalized_cell["signal_tower"] = normalized_signal_tower

	if has_press_machine:
		if typeof(raw_cell["press_machine"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.press_machine 必须是对象" % cell_label)

		var normalized_press_machine: Variant = _parse_press_machine(raw_cell["press_machine"], cell_label, source_label)
		if normalized_press_machine == null:
			return null

		normalized_cell["press_machine"] = normalized_press_machine
		if has_item and String(normalized_cell["item"]["kind"]) != "CARGO":
			return _validation_error(source_label, "%s.press_machine 只能和 item.kind 为 CARGO 的物体共格" % cell_label)

	if has_packer:
		if typeof(raw_cell["packer"]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.packer 必须是对象" % cell_label)

		var normalized_packer: Variant = _parse_packer(raw_cell["packer"], cell_label, source_label)
		if normalized_packer == null:
			return null

		normalized_cell["packer"] = normalized_packer
		if has_item and String(normalized_cell["item"]["kind"]) != "CARGO":
			return _validation_error(source_label, "%s.packer 只能和 item.kind 为 CARGO 的物体共格" % cell_label)

	seen_cells[cell] = true
	return normalized_cell


static func _parse_belt(raw_belt: Dictionary, cell_label: String, source_label: String) -> Variant:
	var belt_label: String = "%s.belt" % cell_label
	if not _ensure_allowed_keys(raw_belt, BELT_KEYS, belt_label, source_label):
		return null

	if not _has_non_empty_string(raw_belt, "input_direction"):
		return _validation_error(source_label, "%s.input_direction 必须是非空字符串" % belt_label)

	if not _has_non_empty_string(raw_belt, "output_direction"):
		return _validation_error(source_label, "%s.output_direction 必须是非空字符串" % belt_label)

	if not _has_positive_integer_number(raw_belt, "beat_interval"):
		return _validation_error(source_label, "%s.beat_interval 必须是正整数" % belt_label)

	var input_direction: String = String(raw_belt["input_direction"]).strip_edges().to_upper()
	var output_direction: String = String(raw_belt["output_direction"]).strip_edges().to_upper()
	var beat_interval: int = int(raw_belt["beat_interval"])

	if not Direction.is_valid_name(input_direction):
		return _validation_error(source_label, "%s.input_direction 必须是 %s 之一" % [belt_label, Direction.NAMES])

	if not Direction.is_valid_name(output_direction):
		return _validation_error(source_label, "%s.output_direction 必须是 %s 之一" % [belt_label, Direction.NAMES])

	if beat_interval != 1 and beat_interval != 2:
		return _validation_error(source_label, "%s.beat_interval 只能是 1 或 2" % belt_label)

	var normalized_input_direction: Direction.Value = Direction.from_name(input_direction)
	var normalized_output_direction: Direction.Value = Direction.from_name(output_direction)
	if Direction.is_opposite(normalized_input_direction, normalized_output_direction):
		return _validation_error(source_label, "%s 不能使用相反的输入/输出方向" % belt_label)

	if normalized_input_direction != normalized_output_direction and not Direction.is_perpendicular(normalized_input_direction, normalized_output_direction):
		return _validation_error(source_label, "%s 的输入/输出方向必须相同或垂直" % belt_label)

	return {
		"input_direction": input_direction,
		"output_direction": output_direction,
		"beat_interval": beat_interval,
	}


static func _parse_item(raw_item: Dictionary, cell_label: String, source_label: String) -> Variant:
	var item_label: String = "%s.item" % cell_label
	if not _ensure_allowed_keys(raw_item, ITEM_KEYS, item_label, source_label):
		return null

	if not _has_non_empty_string(raw_item, "kind"):
		return _validation_error(source_label, "%s.kind 必须是非空字符串" % item_label)

	if not _has_non_empty_string(raw_item, "type"):
		return _validation_error(source_label, "%s.type 必须是非空字符串" % item_label)

	var item_kind: String = String(raw_item["kind"]).strip_edges().to_upper()
	if not ITEM_KIND_VALUES.has(item_kind):
		return _validation_error(source_label, "%s.kind 必须是 %s 之一" % [item_label, ITEM_KIND_VALUES])

	var item_type: String = CargoType.normalize(raw_item["type"])
	if not CargoType.is_valid(item_type):
		return _validation_error(source_label, "%s.type 必须是 %s 之一" % [item_label, CARGO_TYPE_VALUES])

	return {
		"kind": item_kind,
		"type": item_type,
	}


static func _parse_producer(raw_producer: Dictionary, cell_label: String, source_label: String) -> Variant:
	var producer_label: String = "%s.producer" % cell_label
	if not _ensure_allowed_keys(raw_producer, PRODUCER_KEYS, producer_label, source_label):
		return null

	if not _has_non_empty_string(raw_producer, "facing"):
		return _validation_error(source_label, "%s.facing 必须是非空字符串" % producer_label)

	if not _has_positive_integer_number(raw_producer, "beat_interval"):
		return _validation_error(source_label, "%s.beat_interval 必须是正整数" % producer_label)

	if not raw_producer.has("production_sequence") or typeof(raw_producer["production_sequence"]) != TYPE_ARRAY:
		return _validation_error(source_label, "%s.production_sequence 必须是数组" % producer_label)

	var facing: String = String(raw_producer["facing"]).strip_edges().to_upper()
	var beat_interval: int = int(raw_producer["beat_interval"])
	var normalized_sequence: Array[String] = []
	var raw_sequence: Array = Array(raw_producer["production_sequence"])

	if not Direction.is_valid_name(facing):
		return _validation_error(source_label, "%s.facing 必须是 %s 之一" % [producer_label, Direction.NAMES])

	for index in range(raw_sequence.size()):
		if typeof(raw_sequence[index]) != TYPE_STRING:
			return _validation_error(source_label, "%s.production_sequence[%d] 必须是字符串" % [producer_label, index])

		var cargo_type: String = CargoType.normalize(raw_sequence[index])
		if not CargoType.is_valid(cargo_type):
			return _validation_error(source_label, "%s.production_sequence[%d] 必须是 %s 之一" % [producer_label, index, CARGO_TYPE_VALUES])

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
		return _validation_error(source_label, "%s.targets 必须是数组" % recycler_label)

	var raw_targets: Array = Array(raw_recycler["targets"])
	if raw_targets.is_empty():
		return _validation_error(source_label, "%s.targets 至少需要包含一个目标" % recycler_label)

	var normalized_targets: Array[Dictionary] = []
	var seen_product_types: Dictionary = {}
	for index in range(raw_targets.size()):
		if typeof(raw_targets[index]) != TYPE_DICTIONARY:
			return _validation_error(source_label, "%s.targets[%d] 必须是对象" % [recycler_label, index])

		var normalized_target: Variant = _parse_recycler_target(raw_targets[index], recycler_label, index, source_label)
		if normalized_target == null:
			return null

		var product_type: String = String(normalized_target["product_type"])
		if seen_product_types.has(product_type):
			return _validation_error(source_label, "%s.targets[%d].product_type 与 %s 重复" % [recycler_label, index, product_type])

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
		return _validation_error(source_label, "%s.product_type 必须是非空字符串" % target_label)

	if not _has_positive_integer_number(raw_target, "required_count"):
		return _validation_error(source_label, "%s.required_count 必须是正整数" % target_label)

	var product_type: String = CargoType.normalize(raw_target["product_type"])
	if not CargoType.is_valid(product_type):
		return _validation_error(source_label, "%s.product_type 必须是 %s 之一" % [target_label, CARGO_TYPE_VALUES])

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
			return _validation_error(source_label, "%s.max_steps 必须是正整数" % signal_tower_label)

		normalized_signal_tower["max_steps"] = int(raw_signal_tower["max_steps"])

	return normalized_signal_tower


static func _parse_press_machine(raw_press_machine: Dictionary, cell_label: String, source_label: String) -> Variant:
	var press_machine_label: String = "%s.press_machine" % cell_label
	if not _ensure_allowed_keys(raw_press_machine, PRESS_MACHINE_KEYS, press_machine_label, source_label):
		return null

	if not _has_non_empty_string(raw_press_machine, "facing"):
		return _validation_error(source_label, "%s.facing 必须是非空字符串" % press_machine_label)

	if not _has_non_empty_string(raw_press_machine, "cargo_type"):
		return _validation_error(source_label, "%s.cargo_type 必须是非空字符串" % press_machine_label)

	if not _has_positive_integer_number(raw_press_machine, "beat_interval"):
		return _validation_error(source_label, "%s.beat_interval 必须是正整数" % press_machine_label)

	var facing: String = String(raw_press_machine["facing"]).strip_edges().to_upper()
	var cargo_type: String = CargoType.normalize(raw_press_machine["cargo_type"])
	var beat_interval: int = int(raw_press_machine["beat_interval"])

	if not Direction.is_valid_name(facing):
		return _validation_error(source_label, "%s.facing 必须是 %s 之一" % [press_machine_label, Direction.NAMES])

	if not CargoType.is_valid(cargo_type):
		return _validation_error(source_label, "%s.cargo_type 必须是 %s 之一" % [press_machine_label, CARGO_TYPE_VALUES])

	if beat_interval != 1 and beat_interval != 2:
		return _validation_error(source_label, "%s.beat_interval 只能是 1 或 2" % press_machine_label)

	var normalized_press_machine: Dictionary = {
		"facing": facing,
		"cargo_type": cargo_type,
		"beat_interval": beat_interval,
	}

	if raw_press_machine.has("transport_beat_interval"):
		if not _has_positive_integer_number(raw_press_machine, "transport_beat_interval"):
			return _validation_error(source_label, "%s.transport_beat_interval 必须是正整数" % press_machine_label)

		var transport_beat_interval: int = int(raw_press_machine["transport_beat_interval"])
		if transport_beat_interval != 1 and transport_beat_interval != 2:
			return _validation_error(source_label, "%s.transport_beat_interval 只能是 1 或 2" % press_machine_label)

		normalized_press_machine["transport_beat_interval"] = transport_beat_interval

	return normalized_press_machine


static func _parse_packer(raw_packer: Dictionary, cell_label: String, source_label: String) -> Variant:
	var packer_label: String = "%s.packer" % cell_label
	if not _ensure_allowed_keys(raw_packer, PACKER_KEYS, packer_label, source_label):
		return null

	if not _has_non_empty_string(raw_packer, "facing"):
		return _validation_error(source_label, "%s.facing 必须是非空字符串" % packer_label)

	var facing: String = String(raw_packer["facing"]).strip_edges().to_upper()
	if not Direction.is_valid_name(facing):
		return _validation_error(source_label, "%s.facing 必须是 %s 之一" % [packer_label, Direction.NAMES])

	var normalized_packer: Dictionary = {
		"facing": facing,
	}

	if raw_packer.has("transport_beat_interval"):
		if not _has_positive_integer_number(raw_packer, "transport_beat_interval"):
			return _validation_error(source_label, "%s.transport_beat_interval 必须是正整数" % packer_label)

		var transport_beat_interval: int = int(raw_packer["transport_beat_interval"])
		if transport_beat_interval != 1 and transport_beat_interval != 2:
			return _validation_error(source_label, "%s.transport_beat_interval 只能是 1 或 2" % packer_label)

		normalized_packer["transport_beat_interval"] = transport_beat_interval

	return normalized_packer


static func _ensure_allowed_keys(raw_data: Dictionary, allowed_keys: Array, label: String, source_label: String) -> bool:
	for key in raw_data.keys():
		if typeof(key) != TYPE_STRING:
			_push_validation_error(source_label, "%s 中存在非字符串字段名" % label)
			return false

		if not allowed_keys.has(key):
			_push_validation_error(source_label, "%s 中存在未预期字段 '%s'" % [label, key])
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
	_push_validation_error(source_label, message)
	return null


static func _push_validation_error(source_label: String, message: String) -> void:
	var error_message: String = "关卡数据不合法：%s" % message
	_set_last_error_message(error_message)
	push_error("%s（文件：%s）" % [error_message, source_label])


static func _report_error(message: String, source_label: String = "") -> void:
	_set_last_error_message(message)
	if source_label.is_empty():
		push_error(message)
		return

	push_error("%s（文件：%s）" % [message, source_label])


static func _set_last_error_message(message: String) -> void:
	_last_error_message = message
