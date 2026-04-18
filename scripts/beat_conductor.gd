extends Node
class_name BeatConductor

signal beat_fired(beat_index: int, beat_time: float)

@export_range(1.0, 240.0, 1.0) var bpm := 60.0

var _beat_index := 0
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
	beat_fired.emit(_beat_index, Time.get_ticks_msec() / 1000.0)
