extends Node2D
class_name Recycler

const DEFAULT_CARGO_TYPE: String = "CARGO_1"
const CARGO_TEXTURE_1: Texture2D = preload("res://assets/images/cargo_1.png")
const CARGO_TEXTURE_2: Texture2D = preload("res://assets/images/cargo_2.png")
const CARGO_TEXTURE_3: Texture2D = preload("res://assets/images/cargo_3.png")
const IDLE_COLOR: Color = Color(0.93, 0.28, 0.34, 1.0)
const COMPLETE_COLOR: Color = Color(0.27, 0.74, 0.42, 1.0)
const OUTLINE_COLOR: Color = Color(0.15, 0.09, 0.07, 1.0)
const COUNT_BG_COLOR: Color = Color(0.09, 0.11, 0.16, 0.92)
const COUNT_TEXT_COLOR: Color = Color(0.97, 0.95, 0.88, 1.0)
const COMPLETE_RING_COLOR: Color = Color(1.0, 0.93, 0.61, 1.0)
const ICON_SIZE: Vector2 = Vector2(32.0, 32.0)

@export var cargo_type: String = DEFAULT_CARGO_TYPE:
	set(value):
		cargo_type = _normalize_cargo_type(value)
		_update_visual_state()

@export var required_count: int = 1:
	set(value):
		required_count = max(value, 1)
		if remaining_count > required_count:
			remaining_count = required_count
		_update_visual_state()

var remaining_count: int = 1
var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer: bool = false
var _font: Font
@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	remaining_count = required_count

	_world = GM.world
	_register_to_recycler_layer()
	_update_visual_state()


func _exit_tree() -> void:
	_unregister_from_recycler_layer()


func get_registered_cell() -> Vector2i:
	return _registered_cell


func is_completed() -> bool:
	return remaining_count <= 0


func can_accept_cargo(target_cargo_type: String) -> bool:
	return not is_completed() and cargo_type == _normalize_cargo_type(target_cargo_type)


func collect_cargo(target_cargo: Cargo) -> bool:
	if target_cargo == null or not is_instance_valid(target_cargo):
		return false

	var did_collect: bool = can_accept_cargo(target_cargo.cargo_type)
	target_cargo.remove_from_world()
	if did_collect:
		remaining_count -= 1
		_update_visual_state()

	return did_collect


func get_completed_count() -> int:
	return required_count - remaining_count


func get_remaining_count() -> int:
	return remaining_count


func _register_to_recycler_layer() -> void:
	if _world == null:
		return

	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	_world.recycler_layer.set_cell(_registered_cell, self)
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_recycler_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		return

	if _world.recycler_layer.get_cell(_registered_cell) == self:
		_world.recycler_layer.erase_cell(_registered_cell)

	_is_registered_to_layer = false


static func _normalize_cargo_type(value: Variant) -> String:
	var normalized_value: String = String(value).strip_edges().to_upper()
	return normalized_value if not normalized_value.is_empty() else DEFAULT_CARGO_TYPE


func _update_visual_state() -> void:
	if _sprite != null:
		_sprite.modulate = COMPLETE_COLOR if is_completed() else IDLE_COLOR

	queue_redraw()


func _draw() -> void:
	_draw_target_icon()
	_draw_count_badge()
	if is_completed():
		_draw_complete_ring()


func _draw_target_icon() -> void:
	var cargo_texture: Texture2D = _get_texture_for_type(_get_base_cargo_type())
	if cargo_texture == null:
		return

	var icon_rect: Rect2 = Rect2(Vector2(16.0, -18.0), ICON_SIZE)
	draw_texture_rect(cargo_texture, icon_rect, false)
	if _is_advanced_cargo():
		draw_rect(icon_rect.grow(2.0), COMPLETE_RING_COLOR, false, 3.0)


func _draw_count_badge() -> void:
	var display_text: String = "OK" if is_completed() else str(remaining_count)
	var font: Font = _get_draw_font()
	if font == null:
		return

	var font_size: int = 18
	var text_size: Vector2 = font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var badge_size: Vector2 = Vector2(maxf(text_size.x + 18.0, 36.0), 28.0)
	var badge_position: Vector2 = Vector2(32.0 - badge_size.x * 0.5, -46.0)
	var badge_rect: Rect2 = Rect2(badge_position, badge_size)
	draw_rect(badge_rect, COUNT_BG_COLOR, true)
	draw_rect(badge_rect, OUTLINE_COLOR, false, 2.0)

	var text_position: Vector2 = Vector2(
		badge_rect.position.x + (badge_rect.size.x - text_size.x) * 0.5,
		badge_rect.position.y + badge_rect.size.y * 0.5 + text_size.y * 0.35
	)
	draw_string(font, text_position, display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COUNT_TEXT_COLOR)


func _draw_complete_ring() -> void:
	draw_arc(Vector2(32.0, 32.0), 24.0, 0.0, TAU, 24, COMPLETE_RING_COLOR, 3.0)


func _get_draw_font() -> Font:
	if _font != null:
		return _font

	_font = ThemeDB.fallback_font
	return _font


func _get_texture_for_type(type_name: String) -> Texture2D:
	match type_name:
		"CARGO_2":
			return CARGO_TEXTURE_2
		"CARGO_3":
			return CARGO_TEXTURE_3
		_:
			return CARGO_TEXTURE_1


func _get_base_cargo_type() -> String:
	match cargo_type:
		"ADV_CARGO_1":
			return "CARGO_1"
		"ADV_CARGO_2":
			return "CARGO_2"
		"ADV_CARGO_3":
			return "CARGO_3"
		_:
			return cargo_type


func _is_advanced_cargo() -> bool:
	return cargo_type.begins_with("ADV_")
