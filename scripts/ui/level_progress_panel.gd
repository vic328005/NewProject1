extends Control
class_name LevelProgressPanel

const PANEL_BG_COLOR: Color = Color(0.07, 0.08, 0.11, 0.86)
const PANEL_BORDER_COLOR: Color = Color(0.91, 0.82, 0.66, 0.9)
const ITEM_BG_COLOR: Color = Color(0.17, 0.13, 0.11, 0.9)
const ITEM_BORDER_COLOR: Color = Color(0.52, 0.4, 0.32, 0.95)
const ITEM_COMPLETE_BG_COLOR: Color = Color(0.16, 0.28, 0.2, 0.92)
const ITEM_COMPLETE_BORDER_COLOR: Color = Color(0.7, 0.94, 0.72, 0.98)
const COUNT_TEXT_COLOR: Color = Color(0.97, 0.95, 0.88, 1.0)
const COUNT_COMPLETE_TEXT_COLOR: Color = Color(0.92, 1.0, 0.93, 1.0)
const COUNT_OUTLINE_COLOR: Color = Color(0.11, 0.08, 0.07, 0.95)

@onready var progress_card: PanelContainer = $TopRightAnchor/ProgressCard
@onready var item_list: HBoxContainer = $TopRightAnchor/ProgressCard/Content/ItemList

var _beats: BeatConductor
var _panel_style: StyleBoxFlat


func _ready() -> void:
	assert(progress_card != null, "LevelProgressPanel requires a ProgressCard node.")
	assert(item_list != null, "LevelProgressPanel requires an ItemList node.")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beats = GM.beats
	_setup_panel_style()
	_refresh_progress()

	if is_instance_valid(_beats) and not _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.connect(_on_beat_fired)


func _exit_tree() -> void:
	if is_instance_valid(_beats) and _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.disconnect(_on_beat_fired)


func _setup_panel_style() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = PANEL_BG_COLOR
	_panel_style.border_color = PANEL_BORDER_COLOR
	_panel_style.border_width_left = 2
	_panel_style.border_width_top = 2
	_panel_style.border_width_right = 2
	_panel_style.border_width_bottom = 2
	_panel_style.corner_radius_top_left = 18
	_panel_style.corner_radius_top_right = 18
	_panel_style.corner_radius_bottom_right = 18
	_panel_style.corner_radius_bottom_left = 18
	_panel_style.content_margin_left = 18.0
	_panel_style.content_margin_top = 14.0
	_panel_style.content_margin_right = 18.0
	_panel_style.content_margin_bottom = 14.0
	progress_card.add_theme_stylebox_override("panel", _panel_style)


func _refresh_progress() -> void:
	if not is_instance_valid(GM.world):
		visible = false
		return

	var progress_snapshot: Array[Dictionary] = GM.world.get_level_goal_progress_snapshot()
	_rebuild_items(progress_snapshot)
	visible = not progress_snapshot.is_empty()


func _rebuild_items(progress_snapshot: Array[Dictionary]) -> void:
	for child in item_list.get_children():
		child.queue_free()

	for progress in progress_snapshot:
		item_list.add_child(_build_goal_item(progress))


func _build_goal_item(progress: Dictionary) -> Control:
	var is_completed: bool = bool(progress.get("is_completed", false))
	var goal_card: PanelContainer = PanelContainer.new()
	goal_card.custom_minimum_size = Vector2(96.0, 112.0)
	goal_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	goal_card.add_theme_stylebox_override("panel", _create_goal_style(is_completed))

	var content: VBoxContainer = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6)
	goal_card.add_child(content)

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(52.0, 52.0)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.texture = Item.get_product_texture(String(progress.get("product_type", CargoType.DEFAULT)))
	content.add_child(icon_rect)

	var count_label: Label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 24)
	count_label.add_theme_constant_override("outline_size", 4)
	count_label.add_theme_color_override("font_color", COUNT_COMPLETE_TEXT_COLOR if is_completed else COUNT_TEXT_COLOR)
	count_label.add_theme_color_override("font_outline_color", COUNT_OUTLINE_COLOR)
	count_label.text = "%d/%d" % [
		int(progress.get("completed_count", 0)),
		int(progress.get("required_count", 0)),
	]
	content.add_child(count_label)

	return goal_card


func _create_goal_style(is_completed: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = ITEM_COMPLETE_BG_COLOR if is_completed else ITEM_BG_COLOR
	style.border_color = ITEM_COMPLETE_BORDER_COLOR if is_completed else ITEM_BORDER_COLOR
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 10.0
	style.content_margin_top = 10.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 10.0
	return style


func _on_beat_fired(_beat_index: int, _beat_time: float) -> void:
	_refresh_progress()
