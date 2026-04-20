extends Machine
class_name Producer

@export var countdown_texture_1: Texture2D
@export var countdown_texture_2: Texture2D
@export var countdown_texture_3: Texture2D

var facing: Direction.Value = Direction.Value.RIGHT:
	set(value):
		facing = value

var beat_interval: int = 2:
	set(value):
		beat_interval = maxi(value, 1)
		_refresh_countdown_texture()

var production_sequence: Array[String] = []:
	set(value):
		production_sequence = _normalize_production_sequence(value)
		_next_production_index = 0
		_refresh_countdown_texture()
		_refresh_bubble_text()

var _next_production_index: int = 0
var _pending_output_cargo_type: String = ""
var _output_ready_beat: int = -1
var _sprite: Sprite2D
var _bubble_label: Label


func _ready() -> void:
	_connect_beat_signal()
	_refresh_countdown_texture()
	_refresh_bubble_text()
	super._ready()


func _exit_tree() -> void:
	_disconnect_beat_signal()
	super._exit_tree()

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
	_refresh_bubble_text()


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


func _connect_beat_signal() -> void:
	var beats: BeatConductor = _get_beat_conductor()
	if beats == null:
		return

	if not beats.beat_fired.is_connected(_on_beat_fired):
		beats.beat_fired.connect(_on_beat_fired)


func _disconnect_beat_signal() -> void:
	var beats: BeatConductor = _get_beat_conductor()
	if beats == null:
		return

	if beats.beat_fired.is_connected(_on_beat_fired):
		beats.beat_fired.disconnect(_on_beat_fired)


func _on_beat_fired(_beat_index: int, _beat_time: float) -> void:
	# 等当前拍的世界结算完成后再刷新，避免先读到旧状态。
	call_deferred("_refresh_countdown_texture")


func _refresh_countdown_texture() -> void:
	var sprite: Sprite2D = _get_sprite()
	assert(countdown_texture_1 != null, "Producer countdown_texture_1 must be assigned.")
	assert(countdown_texture_2 != null, "Producer countdown_texture_2 must be assigned.")
	assert(countdown_texture_3 != null, "Producer countdown_texture_3 must be assigned.")

	var remaining_beats: int = _get_remaining_beats_until_next_output()
	if remaining_beats <= 1:
		sprite.texture = countdown_texture_1
		return

	if remaining_beats == 2:
		sprite.texture = countdown_texture_2
		return

	sprite.texture = countdown_texture_3


func _refresh_bubble_text() -> void:
	var bubble_label: Label = _get_bubble_label()
	var remaining_count: int = maxi(production_sequence.size() - _next_production_index, 0)
	bubble_label.text = str(remaining_count)


func _get_remaining_beats_until_next_output() -> int:
	if _pending_output_cargo_type != "":
		return _get_remaining_beats_until_ready_output()

	if not has_remaining_production():
		return 3

	return _get_remaining_beats_until_next_trigger() + 1


func _get_remaining_beats_until_ready_output() -> int:
	var current_beat: int = _get_current_beat_index()
	if _output_ready_beat < 0:
		return 1

	# 已进入待出料状态后，至少维持在 1，直到真正出料清空 pending。
	return maxi(_output_ready_beat - current_beat, 1)


func _get_remaining_beats_until_next_trigger() -> int:
	if beat_interval <= 0:
		return 1

	var current_beat: int = _get_current_beat_index()
	var current_cycle_offset: int = current_beat % beat_interval
	if current_cycle_offset == 0:
		return beat_interval

	return beat_interval - current_cycle_offset


func _get_current_beat_index() -> int:
	var beats: BeatConductor = _get_beat_conductor()
	if beats == null:
		return 0

	return beats.get_current_beat_index()


func _get_beat_conductor() -> BeatConductor:
	var beats: BeatConductor = GM.beats
	if not is_instance_valid(beats):
		return null

	return beats


func _get_sprite() -> Sprite2D:
	if _sprite == null:
		_sprite = get_node_or_null(^"Sprite2D") as Sprite2D

	assert(_sprite != null, "Producer must have a Sprite2D child.")
	return _sprite


func _get_bubble_label() -> Label:
	if _bubble_label == null:
		_bubble_label = get_node_or_null(^"ProducerBubble/BubbleLabel") as Label

	assert(_bubble_label != null, "Producer must have a BubbleLabel child under ProducerBubble.")
	return _bubble_label
