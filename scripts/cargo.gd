extends Node2D
class_name Cargo

const MOVE_DURATION_RATIO := 0.9
const DEFAULT_CARGO_TYPE: String = "CARGO_1"
const CARGO_TEXTURE_1: Texture2D = preload("res://assets/images/cargo_1.png")
const CARGO_TEXTURE_2: Texture2D = preload("res://assets/images/cargo_2.png")
const CARGO_TEXTURE_3: Texture2D = preload("res://assets/images/cargo_3.png")
const PACKAGE_FILL_COLOR: Color = Color(0.95, 0.83, 0.57, 0.45)
const PACKAGE_BORDER_COLOR: Color = Color(0.40, 0.26, 0.12, 1.0)
const PACKAGE_RIBBON_COLOR_1: Color = Color(0.84, 0.38, 0.24, 1.0)
const PACKAGE_RIBBON_COLOR_2: Color = Color(0.26, 0.68, 0.42, 1.0)
const PACKAGE_RIBBON_COLOR_3: Color = Color(0.36, 0.44, 0.90, 1.0)

@export var cargo_type: String = DEFAULT_CARGO_TYPE:
	set(value):
		cargo_type = _normalize_cargo_type(value)
		_update_visual_state()

@export var is_packaged: bool = false:
	set(value):
		is_packaged = value
		_update_visual_state()

var _world: World
var _registered_cell: Vector2i
var _is_registered_to_layer := false
var _move_tween: Tween
var last_resolved_beat: int = -1
@onready var _sprite: Sprite2D = $Sprite2D
var _package_fill: Polygon2D
var _package_border: Line2D
var _package_ribbon_horizontal: Line2D
var _package_ribbon_vertical: Line2D


func _ready() -> void:
	_ensure_package_overlay()
	_update_visual_state()

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


func _update_visual_state() -> void:
	if _sprite == null:
		return

	_sprite.texture = _get_texture_for_type(cargo_type)
	_update_package_overlay()


func _get_texture_for_type(type_name: String) -> Texture2D:
	match type_name:
		"CARGO_2":
			return CARGO_TEXTURE_2
		"CARGO_3":
			return CARGO_TEXTURE_3
		_:
			return CARGO_TEXTURE_1


func _ensure_package_overlay() -> void:
	if is_instance_valid(_package_fill):
		return

	# 包装层直接复用几何图形，避免新增贴图资源。
	_package_fill = Polygon2D.new()
	_package_fill.name = "PackageFill"
	_package_fill.z_index = 2
	_package_fill.polygon = PackedVector2Array([
		Vector2(14.0, 14.0),
		Vector2(50.0, 14.0),
		Vector2(50.0, 50.0),
		Vector2(14.0, 50.0),
	])
	add_child(_package_fill)

	_package_border = _create_package_line(
		"PackageBorder",
		PackedVector2Array([
			Vector2(14.0, 14.0),
			Vector2(50.0, 14.0),
			Vector2(50.0, 50.0),
			Vector2(14.0, 50.0),
			Vector2(14.0, 14.0),
		]),
		3.0
	)
	_package_border.z_index = 3
	add_child(_package_border)

	_package_ribbon_horizontal = _create_package_line(
		"PackageRibbonHorizontal",
		PackedVector2Array([
			Vector2(16.0, 32.0),
			Vector2(48.0, 32.0),
		]),
		4.0
	)
	_package_ribbon_horizontal.z_index = 4
	add_child(_package_ribbon_horizontal)

	_package_ribbon_vertical = _create_package_line(
		"PackageRibbonVertical",
		PackedVector2Array([
			Vector2(32.0, 16.0),
			Vector2(32.0, 48.0),
		]),
		4.0
	)
	_package_ribbon_vertical.z_index = 4
	add_child(_package_ribbon_vertical)


func _create_package_line(line_name: String, points: PackedVector2Array, width: float) -> Line2D:
	var line: Line2D = Line2D.new()
	line.name = line_name
	line.points = points
	line.width = width
	line.antialiased = true
	return line


func _update_package_overlay() -> void:
	if not is_instance_valid(_package_fill):
		return

	var ribbon_color: Color = _get_package_ribbon_color()
	_package_fill.color = PACKAGE_FILL_COLOR
	_package_fill.visible = is_packaged
	_package_border.default_color = PACKAGE_BORDER_COLOR
	_package_border.visible = is_packaged
	_package_ribbon_horizontal.default_color = ribbon_color
	_package_ribbon_horizontal.visible = is_packaged
	_package_ribbon_vertical.default_color = ribbon_color
	_package_ribbon_vertical.visible = is_packaged


func _get_package_ribbon_color() -> Color:
	match cargo_type:
		"CARGO_2":
			return PACKAGE_RIBBON_COLOR_2
		"CARGO_3":
			return PACKAGE_RIBBON_COLOR_3
		_:
			return PACKAGE_RIBBON_COLOR_1
