extends Node2D
class_name Cargo

const MOVE_DURATION_RATIO := 0.9
const DEFAULT_CARGO_TYPE: String = "CARGO_1"
const CARGO_TEXTURE_1: Texture2D = preload("res://assets/images/cargo_1.png")
const CARGO_TEXTURE_2: Texture2D = preload("res://assets/images/cargo_2.png")
const CARGO_TEXTURE_3: Texture2D = preload("res://assets/images/cargo_3.png")

@export var cargo_type: String = DEFAULT_CARGO_TYPE:
	set(value):
		cargo_type = _normalize_cargo_type(value)
		_update_sprite_texture()

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer := false
var _move_tween: Tween
var last_resolved_beat: int = -1
@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_update_sprite_texture()

	if _world == null:
		_world = GM.world

	if not _is_registered_to_layer:
		_register_to_cargo_layer()


func _exit_tree() -> void:
	_stop_move_tween()
	_unregister_from_cargo_layer()


func _register_to_cargo_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.cargo_layer.set_cell(_registered_cell, self)
	_stop_move_tween()
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_cargo_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.cargo_layer.get_cell(_registered_cell) == self:
		_world.cargo_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func get_registered_cell() -> Vector2i:
	return _registered_cell


func was_resolved_on_beat(beat_index: int) -> bool:
	return last_resolved_beat == beat_index


func mark_resolved_on_beat(beat_index: int) -> void:
	last_resolved_beat = beat_index


func place_at_cell(world: World, cell: Vector2i) -> void:
	_world = world
	_registered_cell = cell
	_stop_move_tween()
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_world.cargo_layer.set_cell(_registered_cell, self)
	_is_registered_to_layer = true


func move_to_cell(target_cell: Vector2i) -> bool:
	if _world == null:
		return false

	if not _is_registered_to_layer:
		_register_to_cargo_layer()

	if not _is_registered_to_layer:
		return false

	if target_cell == _registered_cell:
		return true

	if _world.cargo_layer.has_cell(target_cell):
		return false

	if _world.cargo_layer.get_cell(_registered_cell) != self:
		return false

	var target_global_position: Vector2 = _world.to_global(_world.cell_to_world(target_cell))
	_world.cargo_layer.erase_cell(_registered_cell)
	_world.cargo_layer.set_cell(target_cell, self)
	_registered_cell = target_cell
	_start_move_to_global_position(target_global_position)
	return true


func remove_from_world() -> void:
	_stop_move_tween()
	_unregister_from_cargo_layer()
	queue_free()


func _start_move_to_global_position(target_global_position: Vector2) -> void:
	_stop_move_tween()

	if global_position.is_equal_approx(target_global_position):
		global_position = target_global_position
		return

	var move_duration: float = _get_move_duration_seconds()
	if move_duration <= 0.0:
		global_position = target_global_position
		return

	_move_tween = create_tween()
	var move_tweener: PropertyTweener = _move_tween.tween_property(self, "global_position", target_global_position, move_duration)
	move_tweener.set_trans(Tween.TRANS_LINEAR)
	_move_tween.finished.connect(_on_move_tween_finished)


func _get_move_duration_seconds() -> float:
	if not is_instance_valid(GM.beats):
		return 0.0

	return maxf(GM.beats.get_beat_interval_seconds() * MOVE_DURATION_RATIO, 0.0)


func _stop_move_tween() -> void:
	if not is_instance_valid(_move_tween):
		return

	_move_tween.kill()
	_move_tween = null


func _on_move_tween_finished() -> void:
	_move_tween = null


static func _normalize_cargo_type(value: Variant) -> String:
	var normalized_value: String = String(value).strip_edges().to_upper()
	return normalized_value if not normalized_value.is_empty() else DEFAULT_CARGO_TYPE


func _update_sprite_texture() -> void:
	if _sprite == null:
		return

	_sprite.texture = _get_texture_for_type(cargo_type)


func _get_texture_for_type(type_name: String) -> Texture2D:
	match type_name:
		"CARGO_2":
			return CARGO_TEXTURE_2
		"CARGO_3":
			return CARGO_TEXTURE_3
		_:
			return CARGO_TEXTURE_1
