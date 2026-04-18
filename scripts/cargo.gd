extends Node2D

var _beat_conductor: BeatConductor
var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer := false


func _ready() -> void:
	_beat_conductor = GM.beat_conductor
	_world = _find_world()

	if not _beat_conductor.beat_fired.is_connected(_on_beat_fired):
		_beat_conductor.beat_fired.connect(_on_beat_fired)

	_register_to_cargo_layer()


func _exit_tree() -> void:
	_unregister_from_cargo_layer()

	if is_instance_valid(_beat_conductor) and _beat_conductor.beat_fired.is_connected(_on_beat_fired):
		_beat_conductor.beat_fired.disconnect(_on_beat_fired)


func _on_beat_fired(beat_index: int, beat_time: float) -> void:
	print("World Beat #%d at %.3f" % [beat_index, beat_time])


func _register_to_cargo_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(position)
	_world.cargo_layer.set_cell(_registered_cell, self)
	_is_registered_to_layer = true


func _unregister_from_cargo_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.cargo_layer.get_cell(_registered_cell) == self:
		_world.cargo_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func _find_world() -> World:
	var current: Node = get_parent()

	while current != null:
		if current is World:
			return current as World
		current = current.get_parent()

	return null
