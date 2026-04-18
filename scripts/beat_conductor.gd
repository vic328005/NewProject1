extends Node
class_name BeatConductor

signal beat_fired(beat_index: int, beat_time: float)

@export_range(1.0, 240.0, 1.0) var bpm: float = 60.0:
	set(value):
		bpm = clampf(float(value), 1.0, 240.0)
		if is_instance_valid(_beat_timer):
			_beat_timer.wait_time = get_beat_interval_seconds()
			if not _beat_timer.is_stopped():
				_beat_timer.start()

var _beat_index: int = 0
var _beat_timer: Timer


func _ready() -> void:
	add_to_group("beat_conductors")
	_start_beat_timer()


func get_beat_interval_seconds() -> float:
	return 60.0 / bpm


func _start_beat_timer() -> void:
	if is_instance_valid(_beat_timer):
		return

	_beat_timer = Timer.new()
	_beat_timer.wait_time = get_beat_interval_seconds()
	_beat_timer.one_shot = false
	_beat_timer.autostart = true
	_beat_timer.timeout.connect(_on_beat_timer_timeout)
	add_child(_beat_timer)


func _on_beat_timer_timeout() -> void:
	_beat_index += 1
	var beat_time: float = Time.get_ticks_msec() / 1000.0
	print("Beat fired: %d at %.3f" % [_beat_index, beat_time])
	beat_fired.emit(_beat_index, beat_time)
