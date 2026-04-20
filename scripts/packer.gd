@tool
extends Node2D
class_name Packer

enum Direction {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

const PREVIEW_CELL_SIZE: float = 64.0
const PREVIEW_CENTER: Vector2 = Vector2(PREVIEW_CELL_SIZE * 0.5, PREVIEW_CELL_SIZE * 0.5)
const BASE_COLOR: Color = Color(0.74, 0.55, 0.28, 1.0)
const PACKAGE_FILL_COLOR: Color = Color(0.92, 0.83, 0.58, 1.0)
const PACKAGE_RIBBON_COLOR: Color = Color(0.55, 0.24, 0.16, 1.0)
const OUTLINE_COLOR: Color = Color(0.18, 0.12, 0.08, 1.0)

@export var facing: Direction = Direction.RIGHT:
	set(value):
		facing = value
		_update_sprite_visual()
		queue_redraw()

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
var _sprite: Sprite2D
var _held_cargo: Cargo
var _pending_output_product_type: String = ""
var _output_ready_beat: int = -1


func _ready() -> void:
	_update_sprite_visual()
	queue_redraw()

	if Engine.is_editor_hint():
		return

	_world = GM.world
	_register_to_packer_layer()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	_unregister_from_packer_layer()


func get_registered_cell() -> Vector2i:
	return _registered_cell


func get_target_cell() -> Vector2i:
	return _registered_cell + _direction_to_offset(facing)


func has_pending_output() -> bool:
	return _pending_output_product_type != ""


func can_output_on_beat(beat_index: int) -> bool:
	return has_pending_output() and beat_index >= _output_ready_beat


func get_pending_output_product_type() -> String:
	assert(has_pending_output(), "Packer has no pending output.")
	return _pending_output_product_type


func commit_output_success() -> void:
	_pending_output_product_type = ""
	_output_ready_beat = -1


func can_accept_input(is_triggered: bool) -> bool:
	_clear_invalid_held_cargo()
	return is_triggered and _held_cargo == null and not has_pending_output()


func accept_input(cargo: Cargo) -> void:
	assert(cargo != null and is_instance_valid(cargo), "Packer requires a valid Cargo to accept input.")
	_clear_invalid_held_cargo()
	assert(_held_cargo == null, "Packer cannot accept input while occupied.")
	cargo.store_in_machine(global_position)
	_held_cargo = cargo


func can_start_cycle(beat_index: int, is_triggered: bool) -> bool:
	_clear_invalid_held_cargo()
	return is_triggered and _held_cargo != null and is_instance_valid(_held_cargo) and not has_pending_output()


func start_cycle(beat_index: int) -> void:
	_clear_invalid_held_cargo()
	assert(_held_cargo != null and is_instance_valid(_held_cargo), "Packer requires held Cargo to start packing.")
	_pending_output_product_type = _held_cargo.cargo_type
	_output_ready_beat = beat_index + 1
	_held_cargo.remove_from_world()
	_held_cargo = null


func allows_pass_through(item: TransportItem, is_triggered: bool) -> bool:
	_clear_invalid_held_cargo()
	if _held_cargo != null or has_pending_output():
		return false

	if item is Cargo and is_triggered:
		return false

	return true


func _clear_invalid_held_cargo() -> void:
	if _held_cargo != null and not is_instance_valid(_held_cargo):
		_held_cargo = null


func _register_to_packer_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.packer_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_packer_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.packer_layer.get_cell(_registered_cell) == self:
		_world.packer_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


func _direction_to_offset(direction: Direction) -> Vector2i:
	match direction:
		Direction.UP:
			return Vector2i.UP
		Direction.RIGHT:
			return Vector2i.RIGHT
		Direction.DOWN:
			return Vector2i.DOWN
		_:
			return Vector2i.LEFT


func _direction_to_vector(direction: Direction) -> Vector2:
	match direction:
		Direction.UP:
			return Vector2.UP
		Direction.RIGHT:
			return Vector2.RIGHT
		Direction.DOWN:
			return Vector2.DOWN
		_:
			return Vector2.LEFT


func _update_sprite_visual() -> void:
	if _sprite == null:
		_sprite = get_node_or_null(^"Sprite2D") as Sprite2D

	if _sprite == null:
		return

	_sprite.modulate = BASE_COLOR


func _draw() -> void:
	var package_rect: Rect2 = Rect2(PREVIEW_CENTER - Vector2(13.0, 13.0), Vector2(26.0, 26.0))
	draw_rect(package_rect, PACKAGE_FILL_COLOR, true)
	draw_rect(package_rect, OUTLINE_COLOR, false, 2.0)
	draw_line(
		Vector2(PREVIEW_CENTER.x, package_rect.position.y),
		Vector2(PREVIEW_CENTER.x, package_rect.end.y),
		PACKAGE_RIBBON_COLOR,
		3.0
	)
	draw_line(
		Vector2(package_rect.position.x, PREVIEW_CENTER.y),
		Vector2(package_rect.end.x, PREVIEW_CENTER.y),
		PACKAGE_RIBBON_COLOR,
		3.0
	)

	var direction: Vector2 = _direction_to_vector(facing)
	var arrow_tip: Vector2 = PREVIEW_CENTER + direction * 20.0
	var arrow_tail: Vector2 = PREVIEW_CENTER + direction * 8.0
	draw_line(arrow_tail, arrow_tip, OUTLINE_COLOR, 4.0)
	_draw_arrow_head(arrow_tip, direction)


func _draw_arrow_head(tip: Vector2, direction: Vector2) -> void:
	var normalized_direction: Vector2 = direction.normalized()
	var normal: Vector2 = Vector2(-normalized_direction.y, normalized_direction.x)
	var arrow_size: float = 8.0
	draw_colored_polygon(
		PackedVector2Array([
			tip,
			tip - normalized_direction * arrow_size + normal * (arrow_size * 0.6),
			tip - normalized_direction * arrow_size - normal * (arrow_size * 0.6),
		]),
		OUTLINE_COLOR
	)
