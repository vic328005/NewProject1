extends Node
class_name GameManager

var event_bus: EventBus
var beat_conductor: BeatConductor


func _init() -> void:
	_ensure_event_bus()
	_ensure_beat_conductor()


func setup() -> void:
	_ensure_event_bus()
	_ensure_beat_conductor()


func emit_event(event_name: StringName, payload: Variant = null) -> void:
	_ensure_event_bus().emit_event(event_name, payload)


func _ensure_event_bus() -> EventBus:
	if is_instance_valid(event_bus):
		return event_bus

	event_bus = EventBus.new()
	event_bus.name = "EventBus"
	add_child(event_bus)
	return event_bus


func _ensure_beat_conductor() -> BeatConductor:
	if is_instance_valid(beat_conductor):
		return beat_conductor

	beat_conductor = BeatConductor.new()
	beat_conductor.name = "BeatConductor"
	add_child(beat_conductor)
	return beat_conductor
