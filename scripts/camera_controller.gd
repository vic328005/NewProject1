extends Node2D
class_name CameraController

const SHAKE_DURATION: float = 0.10
const SHAKE_OFFSET_MAGNITUDE: float = 5.0
const SHAKE_ZOOM_STRENGTH: float = 0.015

@export var camera: Camera2D

var _base_zoom: Vector2 = Vector2.ONE
var _shake_time_left: float = 0.0
var _last_shaken_beat_index: int = -1


func _ready() -> void:
	assert(camera != null, "CameraController requires a Camera2D reference.")
	_base_zoom = camera.zoom
	_subscribe_signal_tower_fired()
	set_process(false)


func _exit_tree() -> void:
	_unsubscribe_signal_tower_fired()
	_reset_shake()


func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		_shake_time_left = 0.0
		set_process(false)
		return

	if _shake_time_left <= 0.0:
		_reset_shake()
		set_process(false)
		return

	var intensity: float = clampf(_shake_time_left / SHAKE_DURATION, 0.0, 1.0)
	camera.offset = Vector2(
		randf_range(-SHAKE_OFFSET_MAGNITUDE, SHAKE_OFFSET_MAGNITUDE),
		randf_range(-SHAKE_OFFSET_MAGNITUDE, SHAKE_OFFSET_MAGNITUDE)
	) * intensity
	var zoom_pulse: float = sin((1.0 - intensity) * PI) * SHAKE_ZOOM_STRENGTH
	camera.zoom = _base_zoom * (1.0 - zoom_pulse)

	_shake_time_left = maxf(_shake_time_left - delta, 0.0)
	if _shake_time_left <= 0.0:
		_reset_shake()
		set_process(false)


func _subscribe_signal_tower_fired() -> void:
	if not is_instance_valid(GM.event):
		return

	var listener: Callable = Callable(self, "_on_signal_tower_fired")
	if not GM.event.has_subscriber(EventDef.signal_tower_fired, listener):
		GM.event.subscribe(EventDef.signal_tower_fired, listener)


func _unsubscribe_signal_tower_fired() -> void:
	if not is_instance_valid(GM.event):
		return

	GM.event.unsubscribe(EventDef.signal_tower_fired, Callable(self, "_on_signal_tower_fired"))


func _on_signal_tower_fired(payload: Variant) -> void:
	if not is_instance_valid(camera) or not (payload is Dictionary):
		return

	var event_payload: Dictionary = payload
	if not event_payload.has("beat_index"):
		return

	var beat_index: int = int(event_payload["beat_index"])
	if beat_index == _last_shaken_beat_index and _shake_time_left > 0.0:
		return

	_last_shaken_beat_index = beat_index
	_start_shake()


func _start_shake() -> void:
	_shake_time_left = SHAKE_DURATION
	camera.offset = Vector2.ZERO
	camera.zoom = _base_zoom
	set_process(true)


func _reset_shake() -> void:
	_shake_time_left = 0.0
	if not is_instance_valid(camera):
		return

	camera.offset = Vector2.ZERO
	camera.zoom = _base_zoom
