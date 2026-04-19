extends Control
class_name MetronomePanel

const MARKER_COUNT: int = 11
const CENTER_MARKER_INDEX: int = MARKER_COUNT / 2
const TRACK_PADDING: float = 64.0
const PULSE_DURATION: float = 0.12
const INPUT_FEEDBACK_DURATION: float = 0.16
const HIT_WINDOW: float = 0.18
const TRACK_COLOR: Color = Color(0.07, 0.08, 0.11, 0.84)
const TRACK_BORDER_COLOR: Color = Color(0.9, 0.92, 0.98, 0.75)
const HIT_ZONE_COLOR: Color = Color(0.45, 0.36, 0.56, 0.32)
const HIT_ZONE_PULSE_COLOR: Color = Color(0.96, 0.8, 0.44, 0.65)
const HIT_ZONE_HIT_COLOR: Color = Color(0.2, 0.84, 0.46, 0.68)
const HIT_ZONE_MISS_COLOR: Color = Color(0.92, 0.3, 0.26, 0.62)
const MARKER_COLOR: Color = Color(0.93, 0.95, 0.98, 0.9)
const MARKER_STRONG_COLOR: Color = Color(1.0, 0.96, 0.82, 1.0)
const MARKER_PULSE_COLOR: Color = Color(1.0, 0.88, 0.48, 1.0)
const MARKER_HIT_COLOR: Color = Color(0.3, 0.96, 0.52, 0.98)
const MARKER_MISS_COLOR: Color = Color(1.0, 0.42, 0.34, 0.95)

enum FeedbackState {
	NONE,
	HIT,
	MISS,
}

@onready var track: Panel = $BottomAnchor/Track
@onready var marker_layer: Control = $BottomAnchor/Track/MarkerLayer
@onready var hit_zone: Panel = $BottomAnchor/Track/HitZone

var _beats: BeatConductor
var _track_style: StyleBoxFlat
var _hit_zone_style: StyleBoxFlat
var _markers: Array[Panel] = []
var _marker_styles: Array[StyleBoxFlat] = []
var _pulse_time_remaining: float = 0.0
var _last_hit_beat_index: int = -1
var _feedback_state: int = FeedbackState.NONE
var _feedback_time_remaining: float = 0.0
var _resolved_beat_index: int = -1


func _ready() -> void:
	assert(track != null, "MetronomePanel requires a Track node.")
	assert(marker_layer != null, "MetronomePanel requires a MarkerLayer node.")
	assert(hit_zone != null, "MetronomePanel requires a HitZone node.")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.clip_contents = true
	_beats = GM.beats
	assert(is_instance_valid(_beats), "MetronomePanel requires GM.beats.")

	_setup_track_style()
	_setup_hit_zone_style()
	_create_markers()

	if not _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.connect(_on_beat_fired)

	_update_visuals()


func _exit_tree() -> void:
	if is_instance_valid(_beats) and _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.disconnect(_on_beat_fired)


func _process(delta: float) -> void:
	if _pulse_time_remaining > 0.0:
		_pulse_time_remaining = maxf(_pulse_time_remaining - delta, 0.0)

	if _feedback_time_remaining > 0.0:
		_feedback_time_remaining = maxf(_feedback_time_remaining - delta, 0.0)
		if _feedback_time_remaining == 0.0:
			_feedback_state = FeedbackState.NONE

	_update_visuals()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_space_press(event):
		return

	if not is_instance_valid(_beats) or not is_instance_valid(GM.world):
		return

	var beat_index: int = _beats.get_current_beat_index()
	if _resolved_beat_index == beat_index:
		get_viewport().set_input_as_handled()
		return

	_resolved_beat_index = beat_index

	var beat_progress: float = _beats.get_beat_progress()
	if _is_hit_timing(beat_progress) and GM.world.try_emit_signal_towers_for_current_beat():
		_trigger_feedback(FeedbackState.HIT)
	else:
		_trigger_feedback(FeedbackState.MISS)

	get_viewport().set_input_as_handled()


func _setup_track_style() -> void:
	_track_style = StyleBoxFlat.new()
	_track_style.bg_color = TRACK_COLOR
	_track_style.border_color = TRACK_BORDER_COLOR
	_track_style.border_width_left = 2
	_track_style.border_width_top = 2
	_track_style.border_width_right = 2
	_track_style.border_width_bottom = 2
	_track_style.corner_radius_top_left = 14
	_track_style.corner_radius_top_right = 14
	_track_style.corner_radius_bottom_right = 14
	_track_style.corner_radius_bottom_left = 14
	track.add_theme_stylebox_override("panel", _track_style)


func _setup_hit_zone_style() -> void:
	_hit_zone_style = StyleBoxFlat.new()
	_hit_zone_style.bg_color = HIT_ZONE_COLOR
	_hit_zone_style.border_color = Color(0.92, 0.94, 0.98, 0.7)
	_hit_zone_style.border_width_left = 2
	_hit_zone_style.border_width_top = 2
	_hit_zone_style.border_width_right = 2
	_hit_zone_style.border_width_bottom = 2
	_hit_zone_style.corner_radius_top_left = 22
	_hit_zone_style.corner_radius_top_right = 22
	_hit_zone_style.corner_radius_bottom_right = 22
	_hit_zone_style.corner_radius_bottom_left = 22
	hit_zone.add_theme_stylebox_override("panel", _hit_zone_style)


func _create_markers() -> void:
	for marker: Panel in _markers:
		if is_instance_valid(marker):
			marker.queue_free()

	_markers.clear()
	_marker_styles.clear()

	for index in range(MARKER_COUNT):
		var marker: Panel = Panel.new()
		var marker_style: StyleBoxFlat = StyleBoxFlat.new()
		marker.name = "Marker%d" % index
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_theme_stylebox_override("panel", marker_style)
		marker_layer.add_child(marker)
		_markers.append(marker)
		_marker_styles.append(marker_style)


func _update_visuals() -> void:
	if not is_instance_valid(_beats):
		return

	var track_size: Vector2 = track.size
	if track_size.x <= 0.0 or track_size.y <= 0.0:
		return

	var current_beat_index: int = _beats.get_current_beat_index()
	var beat_progress: float = _beats.get_beat_progress()
	var center_x: float = track_size.x * 0.5
	var center_y: float = track_size.y * 0.5
	var spacing: float = (track_size.x - TRACK_PADDING * 2.0) / float(MARKER_COUNT - 1)
	var pulse_strength: float = _get_pulse_strength()
	var feedback_strength: float = _get_feedback_strength()

	for index in range(MARKER_COUNT):
		var marker: Panel = _markers[index]
		var marker_style: StyleBoxFlat = _marker_styles[index]
		var offset: int = index - CENTER_MARKER_INDEX
		var absolute_beat_index: int = current_beat_index + offset
		var center_distance: float = absf(absf(float(offset)) - beat_progress)
		var edge_fade: float = clampf(1.0 - center_distance / float(CENTER_MARKER_INDEX + 1), 0.35, 1.0)
		var is_strong_beat: bool = absolute_beat_index > 0 and (absolute_beat_index - 1) % 4 == 0
		var is_hit_marker: bool = absolute_beat_index == _last_hit_beat_index and pulse_strength > 0.0
		var is_feedback_focus: bool = abs(offset) <= 1 and feedback_strength > 0.0

		var marker_height: float = 36.0 if is_strong_beat else 28.0
		var marker_width: float = 12.0 if is_strong_beat else 10.0
		if is_hit_marker:
			marker_height += 12.0 * pulse_strength
			marker_width += 2.0 * pulse_strength
		if is_feedback_focus:
			marker_height += 8.0 * feedback_strength
			marker_width += 2.0 * feedback_strength

		var direction: float = signf(float(offset))
		var marker_x: float = center_x + direction * center_distance * spacing - marker_width * 0.5
		var marker_y: float = center_y - marker_height * 0.5

		marker.position = Vector2(marker_x, marker_y)
		marker.size = Vector2(marker_width, marker_height)

		var fill_color: Color = MARKER_STRONG_COLOR if is_strong_beat else MARKER_COLOR
		if is_hit_marker:
			fill_color = MARKER_PULSE_COLOR
		if is_feedback_focus:
			if _feedback_state == FeedbackState.HIT:
				fill_color = fill_color.lerp(MARKER_HIT_COLOR, feedback_strength)
			elif _feedback_state == FeedbackState.MISS:
				fill_color = fill_color.lerp(MARKER_MISS_COLOR, feedback_strength)
		fill_color.a *= edge_fade

		var border_color: Color = Color(fill_color.r, fill_color.g, fill_color.b, minf(fill_color.a + 0.1, 1.0))
		marker_style.bg_color = fill_color
		marker_style.border_color = border_color
		marker_style.border_width_left = 1
		marker_style.border_width_top = 1
		marker_style.border_width_right = 1
		marker_style.border_width_bottom = 1
		marker_style.corner_radius_top_left = int(round(marker_width * 0.5))
		marker_style.corner_radius_top_right = marker_style.corner_radius_top_left
		marker_style.corner_radius_bottom_right = marker_style.corner_radius_top_left
		marker_style.corner_radius_bottom_left = marker_style.corner_radius_top_left

	_update_hit_zone(pulse_strength, feedback_strength)


func _update_hit_zone(pulse_strength: float, feedback_strength: float) -> void:
	var zone_scale: float = 1.0 + 0.12 * pulse_strength
	var zone_color: Color = HIT_ZONE_COLOR.lerp(HIT_ZONE_PULSE_COLOR, pulse_strength)
	var border_color: Color = TRACK_BORDER_COLOR.lerp(MARKER_PULSE_COLOR, pulse_strength)

	if feedback_strength > 0.0:
		if _feedback_state == FeedbackState.HIT:
			zone_scale += 0.12 * feedback_strength
			zone_color = zone_color.lerp(HIT_ZONE_HIT_COLOR, feedback_strength)
			border_color = border_color.lerp(MARKER_HIT_COLOR, feedback_strength)
		elif _feedback_state == FeedbackState.MISS:
			zone_scale -= 0.08 * feedback_strength
			zone_color = zone_color.lerp(HIT_ZONE_MISS_COLOR, feedback_strength)
			border_color = border_color.lerp(MARKER_MISS_COLOR, feedback_strength)

	hit_zone.scale = Vector2.ONE * zone_scale
	hit_zone.modulate = Color(1.0, 1.0, 1.0, 0.96 + 0.04 * pulse_strength)
	_hit_zone_style.bg_color = zone_color
	_hit_zone_style.border_color = border_color


func _get_pulse_strength() -> float:
	if _pulse_time_remaining <= 0.0:
		return 0.0

	var normalized_time: float = _pulse_time_remaining / PULSE_DURATION
	return sin(normalized_time * PI * 0.5)


func _get_feedback_strength() -> float:
	if _feedback_time_remaining <= 0.0:
		return 0.0

	return _feedback_time_remaining / INPUT_FEEDBACK_DURATION


func _trigger_feedback(feedback_state: int) -> void:
	_feedback_state = feedback_state
	_feedback_time_remaining = INPUT_FEEDBACK_DURATION


func _is_space_press(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false

	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return false

	return key_event.keycode == KEY_SPACE or key_event.physical_keycode == KEY_SPACE


func _is_hit_timing(beat_progress: float) -> bool:
	return minf(beat_progress, 1.0 - beat_progress) <= HIT_WINDOW


func _on_beat_fired(beat_index: int, _beat_time: float) -> void:
	_last_hit_beat_index = beat_index
	_pulse_time_remaining = PULSE_DURATION
	_resolved_beat_index = -1
