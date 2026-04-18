extends Node
class_name EventBus

signal event_emitted(event_name: StringName, payload: Variant)

const _CALLABLE_KEY := &"callable"
const _ONESHOT_KEY := &"oneshot"

var _listeners: Dictionary = {}


func subscribe(event_name: StringName, listener: Callable, oneshot: bool = false) -> bool:
	if String(event_name).is_empty():
		push_warning("EventBus.subscribe received an empty event name.")
		return false

	if not listener.is_valid():
		push_warning("EventBus.subscribe received an invalid listener for '%s'." % String(event_name))
		return false

	var listeners: Array = _listeners.get(event_name, [])
	if _find_listener_index(listeners, listener) != -1:
		return false

	listeners.append({
		_CALLABLE_KEY: listener,
		_ONESHOT_KEY: oneshot,
	})
	_listeners[event_name] = listeners
	return true


func unsubscribe(event_name: StringName, listener: Callable) -> bool:
	if not _listeners.has(event_name):
		return false

	var listeners: Array = _listeners[event_name]
	var index := _find_listener_index(listeners, listener)
	if index == -1:
		return false

	listeners.remove_at(index)

	if listeners.is_empty():
		_listeners.erase(event_name)
	else:
		_listeners[event_name] = listeners

	return true


func has_subscriber(event_name: StringName, listener: Callable) -> bool:
	var listeners: Array = _listeners.get(event_name, [])
	return _find_listener_index(listeners, listener) != -1


func has_listeners(event_name: StringName) -> bool:
	if not _listeners.has(event_name):
		return false

	var listeners: Array = _listeners[event_name]
	var valid_listeners: Array = []

	for entry in listeners:
		var listener: Callable = entry[_CALLABLE_KEY]
		if listener.is_valid():
			valid_listeners.append(entry)

	if valid_listeners.size() != listeners.size():
		if valid_listeners.is_empty():
			_listeners.erase(event_name)
		else:
			_listeners[event_name] = valid_listeners

	return not valid_listeners.is_empty()


func emit_event(event_name: StringName, payload: Variant = null) -> void:
	var listeners: Array = _listeners.get(event_name, []).duplicate()

	for entry in listeners:
		var listener: Callable = entry[_CALLABLE_KEY]
		if not listener.is_valid():
			unsubscribe(event_name, listener)
			continue

		listener.call(payload)

		if entry[_ONESHOT_KEY]:
			unsubscribe(event_name, listener)

	event_emitted.emit(event_name, payload)


func clear(event_name: StringName) -> void:
	_listeners.erase(event_name)


func clear_all() -> void:
	_listeners.clear()


func _find_listener_index(listeners: Array, listener: Callable) -> int:
	for index in range(listeners.size()):
		if listeners[index][_CALLABLE_KEY] == listener:
			return index

	return -1
