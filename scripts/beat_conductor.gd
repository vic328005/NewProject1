extends Node
class_name BeatConductor

signal beat_fired(beat_index: int, beat_time: float)

const MIN_BPM: float = 1.0
const MAX_BPM: float = 240.0
const DEFAULT_BPM: float = 160.0

var _bpm: float = DEFAULT_BPM

var _beat_index: int = 0
var _beat_timer: Timer
var _last_beat_time_seconds: float = 0.0
var _is_running: bool = false


func _ready() -> void:
	_start_beat_timer()


func set_bpm(value: float) -> void:
	_bpm = clampf(float(value), MIN_BPM, MAX_BPM)
	if not is_instance_valid(_beat_timer):
		return

	_beat_timer.wait_time = get_beat_interval_seconds()
	if not _beat_timer.is_stopped():
		_beat_timer.start()


func get_bpm() -> float:
	return _bpm


func get_beat_interval_seconds() -> float:
	return 60.0 / _bpm


func get_current_beat_index() -> int:
	return _beat_index


func get_beat_progress(now_time: float = -1.0) -> float:
	if not _is_running:
		return 0.0

	if not is_instance_valid(_beat_timer):
		return 0.0

	var sample_time: float = now_time
	if sample_time < 0.0:
		sample_time = _get_time_seconds()

	var interval_seconds: float = get_beat_interval_seconds()
	if interval_seconds <= 0.0:
		return 0.0

	return clampf((sample_time - _last_beat_time_seconds) / interval_seconds, 0.0, 1.0)


func reset(next_bpm: float = -1.0) -> void:
	_beat_index = 0
	if next_bpm > 0.0:
		_bpm = clampf(float(next_bpm), MIN_BPM, MAX_BPM)

	_last_beat_time_seconds = _get_time_seconds()

	if not is_instance_valid(_beat_timer):
		return

	_beat_timer.stop()
	_beat_timer.wait_time = get_beat_interval_seconds()


func start() -> void:
	_start_beat_timer()
	_is_running = true
	_last_beat_time_seconds = _get_time_seconds()
	_beat_timer.wait_time = get_beat_interval_seconds()
	_beat_timer.start()


func stop() -> void:
	_is_running = false

	if not is_instance_valid(_beat_timer):
		return

	_beat_timer.stop()


func is_running() -> bool:
	return _is_running


func _start_beat_timer() -> void:
	if is_instance_valid(_beat_timer):
		return

	_beat_timer = Timer.new()
	_beat_timer.wait_time = get_beat_interval_seconds()
	_beat_timer.one_shot = false
	_beat_timer.timeout.connect(_on_beat_timer_timeout)
	add_child(_beat_timer)
	_last_beat_time_seconds = _get_time_seconds()


func _on_beat_timer_timeout() -> void:
	if not _is_running:
		return

	_beat_index += 1
	var beat_time: float = _get_time_seconds()
	_last_beat_time_seconds = beat_time
	print("Beat fired: %d at %.3f" % [_beat_index, beat_time])
	beat_fired.emit(_beat_index, beat_time)


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
