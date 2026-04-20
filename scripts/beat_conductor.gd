extends Node
class_name BeatConductor

signal beat_fired(beat_index: int, beat_time: float)

const MIN_BPM: float = 1.0
const MAX_BPM: float = 240.0
const DEFAULT_BPM: float = 160.0

var _bpm: float = DEFAULT_BPM
var _beat_index: int = 0
var _is_running: bool = false
var _fallback_start_time_seconds: float = 0.0


func _ready() -> void:
	set_process(false)
	_fallback_start_time_seconds = _get_time_seconds()


func _process(_delta: float) -> void:
	_sync_beats_from_timeline()


func set_bpm(value: float) -> void:
	_bpm = clampf(float(value), MIN_BPM, MAX_BPM)


func get_bpm() -> float:
	return _bpm


func get_beat_interval_seconds() -> float:
	return 60.0 / _bpm


func get_current_beat_index() -> int:
	return _beat_index


func get_beat_progress(now_time: float = -1.0) -> float:
	if not _is_running:
		return 0.0

	return _sample_timeline_state(now_time)["beat_progress"]


func reset(next_bpm: float = -1.0) -> void:
	_beat_index = 0
	if next_bpm > 0.0:
		_bpm = clampf(float(next_bpm), MIN_BPM, MAX_BPM)

	_fallback_start_time_seconds = _get_time_seconds()


func start() -> void:
	_is_running = true
	_fallback_start_time_seconds = _get_time_seconds()
	set_process(true)


func stop() -> void:
	_is_running = false
	set_process(false)


func is_running() -> bool:
	return _is_running


func _sync_beats_from_timeline() -> void:
	if not _is_running:
		return

	var timeline_state: Dictionary = _sample_timeline_state()
	var sampled_beat_index: int = int(timeline_state["beat_index"])
	if sampled_beat_index <= _beat_index:
		return

	var beat_time: float = _get_time_seconds()
	for next_beat_index in range(_beat_index + 1, sampled_beat_index + 1):
		_beat_index = next_beat_index
		print("Beat fired: %d at %.3f" % [_beat_index, beat_time])
		beat_fired.emit(_beat_index, beat_time)


func _sample_timeline_state(now_time: float = -1.0) -> Dictionary:
	var interval_seconds: float = get_beat_interval_seconds()
	if interval_seconds <= 0.0:
		return {
			"beat_index": _beat_index,
			"beat_progress": 0.0,
		}

	var relative_time_seconds: float = _get_relative_timeline_seconds(now_time)
	if relative_time_seconds >= 0.0:
		var beat_float: float = relative_time_seconds / interval_seconds
		var completed_beats: int = int(floor(beat_float))
		return {
			"beat_index": completed_beats,
			"beat_progress": beat_float - float(completed_beats),
		}

	# 拍格起点尚未到来时，先停在 0，避免开局因音频延迟出现假进度回绕。
	return {
		"beat_index": 0,
		"beat_progress": 0.0,
	}


func _get_relative_timeline_seconds(now_time: float = -1.0) -> float:
	var audio: AudioController = GM.audio
	if is_instance_valid(audio) and audio.has_game_bgm_timeline():
		return audio.get_game_bgm_beat_timeline_seconds()

	var sample_time: float = now_time
	if sample_time < 0.0:
		sample_time = _get_time_seconds()

	return sample_time - _fallback_start_time_seconds


func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
