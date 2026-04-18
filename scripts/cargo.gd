extends Node2D

var _beat_conductor: BeatConductor


func _ready() -> void:
	_beat_conductor = GM.beat_conductor

	if not _beat_conductor.beat_fired.is_connected(_on_beat_fired):
		_beat_conductor.beat_fired.connect(_on_beat_fired)


func _exit_tree() -> void:
	if is_instance_valid(_beat_conductor) and _beat_conductor.beat_fired.is_connected(_on_beat_fired):
		_beat_conductor.beat_fired.disconnect(_on_beat_fired)


func _on_beat_fired(beat_index: int, beat_time: float) -> void:
	print("World Beat #%d at %.3f" % [beat_index, beat_time])
