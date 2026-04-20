extends Control
class_name LevelProgressPanel


class GoalItemView:
	extends RefCounted

	var product_type: String = ""
	var goal_card: PanelContainer
	var visual_root: Control
	var content: VBoxContainer
	var icon_rect: TextureRect
	var count_label: Label
	var overlay_layer: Control
	var goal_style: StyleBoxFlat
	var is_completed: bool = false
	var feedback_tween: Tween


const PANEL_BG_COLOR: Color = Color(0.07, 0.08, 0.11, 0.86)
const PANEL_BORDER_COLOR: Color = Color(0.91, 0.82, 0.66, 0.9)
const ITEM_BG_COLOR: Color = Color(0.17, 0.13, 0.11, 0.9)
const ITEM_BORDER_COLOR: Color = Color(0.52, 0.4, 0.32, 0.95)
const ITEM_COMPLETE_BG_COLOR: Color = Color(0.16, 0.28, 0.2, 0.92)
const ITEM_COMPLETE_BORDER_COLOR: Color = Color(0.7, 0.94, 0.72, 0.98)
const COUNT_TEXT_COLOR: Color = Color(0.97, 0.95, 0.88, 1.0)
const COUNT_COMPLETE_TEXT_COLOR: Color = Color(0.92, 1.0, 0.93, 1.0)
const COUNT_OUTLINE_COLOR: Color = Color(0.11, 0.08, 0.07, 0.95)
const FAILURE_TRACK_BG_COLOR: Color = Color(0.13, 0.1, 0.09, 0.9)
const FAILURE_TRACK_BORDER_COLOR: Color = Color(0.45, 0.35, 0.29, 0.95)
const FAILURE_SAFE_FILL_COLOR: Color = Color(0.35, 0.78, 0.46, 0.96)
const FAILURE_WARNING_FILL_COLOR: Color = Color(0.91, 0.65, 0.24, 0.98)
const FAILURE_DANGER_FILL_COLOR: Color = Color(0.9, 0.27, 0.24, 1.0)
const FAILURE_LABEL_COLOR: Color = Color(0.95, 0.93, 0.88, 1.0)
const FAILURE_LABEL_OUTLINE_COLOR: Color = Color(0.1, 0.08, 0.07, 0.95)
const FAILURE_HIGH_RISK_THRESHOLD: float = 0.8
const GOAL_FEEDBACK_DURATION: float = 0.36
const GOAL_FEEDBACK_SCALE: float = 1.14
const GOAL_COUNT_FEEDBACK_SCALE: float = 1.22
const GOAL_FEEDBACK_BG_COLOR: Color = Color(0.48, 0.31, 0.14, 1.0)
const GOAL_FEEDBACK_COMPLETE_BG_COLOR: Color = Color(0.34, 0.5, 0.28, 1.0)
const GOAL_FEEDBACK_BORDER_COLOR: Color = Color(1.0, 0.97, 0.78, 1.0)
const GOAL_FEEDBACK_COMPLETE_BORDER_COLOR: Color = Color(0.98, 1.0, 0.9, 1.0)
const COUNT_FEEDBACK_TEXT_COLOR: Color = Color(1.0, 1.0, 0.92, 1.0)
const GOAL_FEEDBACK_OUTLINE_SIZE: int = 6
const GOAL_FEEDBACK_BORDER_WIDTH: int = 4
const POPUP_TEXT_COLOR: Color = Color(1.0, 0.98, 0.8, 1.0)
const POPUP_OUTLINE_COLOR: Color = Color(0.08, 0.05, 0.04, 1.0)
const POPUP_RISE_DISTANCE: float = 30.0
const POPUP_START_SCALE: float = 0.72
const POPUP_PEAK_SCALE: float = 1.18
const GOAL_CARD_MIN_SIZE: Vector2 = Vector2(96.0, 112.0)

@onready var progress_card: PanelContainer = $TopRightAnchor/ProgressCard
@onready var item_list: HBoxContainer = $TopRightAnchor/ProgressCard/Content/Stack/ItemList
@onready var failure_track: Panel = $TopRightAnchor/ProgressCard/Content/Stack/FailureSection/FailureTrack
@onready var failure_fill: ColorRect = $TopRightAnchor/ProgressCard/Content/Stack/FailureSection/FailureTrack/FailureFill
@onready var failure_label: Label = $TopRightAnchor/ProgressCard/Content/Stack/FailureSection/FailureLabel

var _beats: BeatConductor
var _panel_style: StyleBoxFlat
var _failure_track_style: StyleBoxFlat
var _goal_item_views: Dictionary = {}
var _previous_progress_by_product: Dictionary = {}
var _has_progress_baseline: bool = false


func _ready() -> void:
	assert(progress_card != null, "LevelProgressPanel requires a ProgressCard node.")
	assert(item_list != null, "LevelProgressPanel requires an ItemList node.")
	assert(failure_track != null, "LevelProgressPanel requires a FailureTrack node.")
	assert(failure_fill != null, "LevelProgressPanel requires a FailureFill node.")
	assert(failure_label != null, "LevelProgressPanel requires a FailureLabel node.")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beats = GM.beats
	_setup_panel_style()
	_setup_failure_track_style()
	_refresh_progress()
	_refresh_failure_progress()

	if is_instance_valid(_beats) and not _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.connect(_on_beat_fired)


func _exit_tree() -> void:
	if is_instance_valid(_beats) and _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.disconnect(_on_beat_fired)


func _process(_delta: float) -> void:
	_refresh_failure_progress()


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


func _setup_failure_track_style() -> void:
	_failure_track_style = StyleBoxFlat.new()
	_failure_track_style.bg_color = FAILURE_TRACK_BG_COLOR
	_failure_track_style.border_color = FAILURE_TRACK_BORDER_COLOR
	_failure_track_style.border_width_left = 2
	_failure_track_style.border_width_top = 2
	_failure_track_style.border_width_right = 2
	_failure_track_style.border_width_bottom = 2
	_failure_track_style.corner_radius_top_left = 8
	_failure_track_style.corner_radius_top_right = 8
	_failure_track_style.corner_radius_bottom_right = 8
	_failure_track_style.corner_radius_bottom_left = 8
	failure_track.add_theme_stylebox_override("panel", _failure_track_style)
	failure_label.add_theme_font_size_override("font_size", 15)
	failure_label.add_theme_constant_override("outline_size", 3)
	failure_label.add_theme_color_override("font_color", FAILURE_LABEL_COLOR)
	failure_label.add_theme_color_override("font_outline_color", FAILURE_LABEL_OUTLINE_COLOR)


func _refresh_progress() -> void:
	if not is_instance_valid(GM.world):
		visible = false
		_clear_goal_items()
		_reset_progress_tracking()
		_refresh_failure_progress()
		return

	var progress_snapshot: Array[Dictionary] = GM.world.get_level_goal_progress_snapshot()
	if progress_snapshot.is_empty():
		visible = false
		_clear_goal_items()
		_reset_progress_tracking()
		return

	if _should_reset_progress_tracking(progress_snapshot):
		_reset_progress_tracking()

	_sync_goal_items(progress_snapshot)
	_previous_progress_by_product = _index_progress_snapshot(progress_snapshot)
	_has_progress_baseline = true
	visible = true


func _sync_goal_items(progress_snapshot: Array[Dictionary]) -> void:
	var active_products: Dictionary = {}
	for index in range(progress_snapshot.size()):
		var progress: Dictionary = progress_snapshot[index]
		var product_type: String = String(progress.get("product_type", CargoType.DEFAULT))
		active_products[product_type] = true

		var goal_item: GoalItemView = _ensure_goal_item_view(product_type)
		_update_goal_item(goal_item, progress)
		if item_list.get_child(index) != goal_item.goal_card:
			item_list.move_child(goal_item.goal_card, index)

		if _has_progress_baseline:
			var previous_progress: Dictionary = _previous_progress_by_product.get(product_type, {})
			var delta_completed_count: int = int(progress.get("completed_count", 0)) - int(previous_progress.get("completed_count", 0))
			if delta_completed_count > 0:
				_trigger_goal_feedback(goal_item, delta_completed_count)

	_remove_stale_goal_items(active_products)


func _ensure_goal_item_view(product_type: String) -> GoalItemView:
	if _goal_item_views.has(product_type):
		return _goal_item_views[product_type] as GoalItemView

	var goal_item: GoalItemView = _build_goal_item(product_type)
	_goal_item_views[product_type] = goal_item
	item_list.add_child(goal_item.goal_card)
	return goal_item


func _build_goal_item(product_type: String) -> GoalItemView:
	var goal_item: GoalItemView = GoalItemView.new()
	goal_item.product_type = product_type

	var goal_card: PanelContainer = PanelContainer.new()
	goal_card.custom_minimum_size = GOAL_CARD_MIN_SIZE
	goal_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	goal_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goal_card.resized.connect(_update_control_pivot.bind(goal_card))
	goal_item.goal_card = goal_card

	var goal_style: StyleBoxFlat = _create_goal_style(false)
	goal_card.add_theme_stylebox_override("panel", goal_style)
	goal_item.goal_style = goal_style

	var visual_root: Control = Control.new()
	visual_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(visual_root)
	goal_card.add_child(visual_root)
	goal_item.visual_root = visual_root

	var content: VBoxContainer = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	_fill_parent(content)
	visual_root.add_child(content)
	goal_item.content = content

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(52.0, 52.0)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.texture = Item.get_product_texture(product_type)
	content.add_child(icon_rect)
	goal_item.icon_rect = icon_rect

	var count_label: Label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_font_size_override("font_size", 24)
	count_label.add_theme_constant_override("outline_size", 4)
	count_label.add_theme_color_override("font_outline_color", COUNT_OUTLINE_COLOR)
	count_label.resized.connect(_update_control_pivot.bind(count_label))
	content.add_child(count_label)
	goal_item.count_label = count_label

	var overlay_layer: Control = Control.new()
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_parent(overlay_layer)
	visual_root.add_child(overlay_layer)
	goal_item.overlay_layer = overlay_layer

	_update_control_pivot(goal_card)
	_update_control_pivot(count_label)
	_apply_goal_feedback_strength(0.0, goal_item)
	return goal_item


func _fill_parent(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _update_goal_item(goal_item: GoalItemView, progress: Dictionary) -> void:
	goal_item.is_completed = bool(progress.get("is_completed", false))
	goal_item.icon_rect.texture = Item.get_product_texture(String(progress.get("product_type", goal_item.product_type)))
	goal_item.count_label.text = "%d/%d" % [
		int(progress.get("completed_count", 0)),
		int(progress.get("required_count", 0)),
	]
	_apply_goal_feedback_strength(0.0, goal_item)


func _remove_stale_goal_items(active_products: Dictionary) -> void:
	for product_variant in _goal_item_views.keys():
		var product_type: String = String(product_variant)
		if active_products.has(product_type):
			continue

		var goal_item: GoalItemView = _goal_item_views[product_type] as GoalItemView
		if goal_item != null and goal_item.feedback_tween != null and goal_item.feedback_tween.is_valid():
			goal_item.feedback_tween.kill()
		if goal_item != null and goal_item.goal_card != null:
			goal_item.goal_card.queue_free()
		_goal_item_views.erase(product_type)


func _clear_goal_items() -> void:
	for goal_item_variant in _goal_item_views.values():
		var goal_item: GoalItemView = goal_item_variant as GoalItemView
		if goal_item == null:
			continue
		if goal_item.feedback_tween != null and goal_item.feedback_tween.is_valid():
			goal_item.feedback_tween.kill()
		if goal_item.goal_card != null:
			goal_item.goal_card.queue_free()

	_goal_item_views.clear()


func _reset_progress_tracking() -> void:
	_previous_progress_by_product.clear()
	_has_progress_baseline = false


func _should_reset_progress_tracking(progress_snapshot: Array[Dictionary]) -> bool:
	if not _has_progress_baseline:
		return false

	var current_progress_by_product: Dictionary = _index_progress_snapshot(progress_snapshot)
	for product_variant in current_progress_by_product.keys():
		var product_type: String = String(product_variant)
		if not _previous_progress_by_product.has(product_type):
			return true

		var current_progress: Dictionary = current_progress_by_product[product_type]
		var previous_progress: Dictionary = _previous_progress_by_product[product_type]
		if int(current_progress.get("required_count", 0)) != int(previous_progress.get("required_count", 0)):
			return true
		if int(current_progress.get("completed_count", 0)) < int(previous_progress.get("completed_count", 0)):
			return true

	for product_variant in _previous_progress_by_product.keys():
		var product_type: String = String(product_variant)
		if not current_progress_by_product.has(product_type):
			return true

	return false


func _index_progress_snapshot(progress_snapshot: Array[Dictionary]) -> Dictionary:
	var indexed_progress: Dictionary = {}
	for progress in progress_snapshot:
		var product_type: String = String(progress.get("product_type", CargoType.DEFAULT))
		indexed_progress[product_type] = progress.duplicate(true)

	return indexed_progress


func _trigger_goal_feedback(goal_item: GoalItemView, delta_completed_count: int) -> void:
	if goal_item.feedback_tween != null and goal_item.feedback_tween.is_valid():
		goal_item.feedback_tween.kill()

	goal_item.goal_card.scale = Vector2.ONE * GOAL_FEEDBACK_SCALE
	goal_item.count_label.scale = Vector2.ONE * GOAL_COUNT_FEEDBACK_SCALE
	_apply_goal_feedback_strength(1.0, goal_item)
	_spawn_progress_popup(goal_item, delta_completed_count)

	var feedback_tween: Tween = create_tween()
	feedback_tween.set_parallel(true)
	feedback_tween.tween_property(goal_item.goal_card, "scale", Vector2.ONE, GOAL_FEEDBACK_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	feedback_tween.tween_property(goal_item.count_label, "scale", Vector2.ONE, GOAL_FEEDBACK_DURATION * 0.85).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	feedback_tween.tween_method(Callable(self, "_apply_goal_feedback_strength").bind(goal_item), 1.0, 0.0, GOAL_FEEDBACK_DURATION)
	feedback_tween.finished.connect(_on_goal_feedback_finished.bind(goal_item), CONNECT_ONE_SHOT)
	goal_item.feedback_tween = feedback_tween


func _apply_goal_feedback_strength(strength: float, goal_item: GoalItemView) -> void:
	var boosted_strength: float = pow(strength, 0.58)
	var base_bg_color: Color = _get_goal_bg_color(goal_item.is_completed)
	var base_border_color: Color = _get_goal_border_color(goal_item.is_completed)
	var base_count_color: Color = _get_goal_count_color(goal_item.is_completed)
	var feedback_bg_color: Color = GOAL_FEEDBACK_COMPLETE_BG_COLOR if goal_item.is_completed else GOAL_FEEDBACK_BG_COLOR
	var feedback_border_color: Color = GOAL_FEEDBACK_COMPLETE_BORDER_COLOR if goal_item.is_completed else GOAL_FEEDBACK_BORDER_COLOR

	goal_item.goal_style.bg_color = base_bg_color.lerp(feedback_bg_color, boosted_strength)
	goal_item.goal_style.border_color = base_border_color.lerp(feedback_border_color, boosted_strength)
	goal_item.goal_style.border_width_left = int(round(lerpf(2.0, float(GOAL_FEEDBACK_BORDER_WIDTH), boosted_strength)))
	goal_item.goal_style.border_width_top = goal_item.goal_style.border_width_left
	goal_item.goal_style.border_width_right = goal_item.goal_style.border_width_left
	goal_item.goal_style.border_width_bottom = goal_item.goal_style.border_width_left
	goal_item.count_label.add_theme_color_override("font_color", base_count_color.lerp(COUNT_FEEDBACK_TEXT_COLOR, boosted_strength))
	goal_item.count_label.add_theme_constant_override("outline_size", int(round(lerpf(4.0, float(GOAL_FEEDBACK_OUTLINE_SIZE), boosted_strength))))
	goal_item.visual_root.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(1.0, 0.98, 0.92, 1.0), boosted_strength)


func _spawn_progress_popup(goal_item: GoalItemView, delta_completed_count: int) -> void:
	var popup_label: Label = Label.new()
	popup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_label.text = "+%d" % delta_completed_count
	popup_label.add_theme_font_size_override("font_size", 30)
	popup_label.add_theme_constant_override("outline_size", 6)
	popup_label.add_theme_color_override("font_color", POPUP_TEXT_COLOR)
	popup_label.add_theme_color_override("font_outline_color", POPUP_OUTLINE_COLOR)
	popup_label.scale = Vector2.ONE * POPUP_START_SCALE
	goal_item.overlay_layer.add_child(popup_label)

	var label_size: Vector2 = popup_label.get_combined_minimum_size()
	popup_label.size = label_size

	var overlay_rect: Rect2 = goal_item.overlay_layer.get_global_rect()
	var count_rect: Rect2 = goal_item.count_label.get_global_rect()
	var start_position: Vector2 = count_rect.position - overlay_rect.position
	start_position.x += (count_rect.size.x - label_size.x) * 0.5
	start_position.y -= label_size.y * 0.7
	popup_label.position = start_position
	popup_label.modulate = POPUP_TEXT_COLOR

	var popup_tween: Tween = create_tween()
	popup_tween.set_parallel(true)
	popup_tween.tween_property(popup_label, "position", start_position + Vector2(0.0, -POPUP_RISE_DISTANCE), GOAL_FEEDBACK_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	popup_tween.tween_property(popup_label, "scale", Vector2.ONE * POPUP_PEAK_SCALE, GOAL_FEEDBACK_DURATION * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	popup_tween.chain().tween_property(popup_label, "scale", Vector2.ONE, GOAL_FEEDBACK_DURATION * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	popup_tween.tween_property(popup_label, "modulate", Color(POPUP_TEXT_COLOR.r, POPUP_TEXT_COLOR.g, POPUP_TEXT_COLOR.b, 0.0), GOAL_FEEDBACK_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	popup_tween.finished.connect(_on_popup_tween_finished.bind(popup_label), CONNECT_ONE_SHOT)


func _get_goal_bg_color(is_completed: bool) -> Color:
	if is_completed:
		return ITEM_COMPLETE_BG_COLOR
	return ITEM_BG_COLOR


func _get_goal_border_color(is_completed: bool) -> Color:
	if is_completed:
		return ITEM_COMPLETE_BORDER_COLOR
	return ITEM_BORDER_COLOR


func _get_goal_count_color(is_completed: bool) -> Color:
	if is_completed:
		return COUNT_COMPLETE_TEXT_COLOR
	return COUNT_TEXT_COLOR


func _create_goal_style(is_completed: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = _get_goal_bg_color(is_completed)
	style.border_color = _get_goal_border_color(is_completed)
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


func _refresh_failure_progress() -> void:
	if failure_fill == null or failure_label == null or failure_track == null:
		return

	var beat_limit: int = max(GM.current_level_failure_beat_limit, 0)
	if beat_limit <= 0:
		failure_fill.size.x = 0.0
		failure_label.text = "BEATS -- / --"
		return

	var beat_progress: float = 0.0
	if is_instance_valid(_beats):
		beat_progress = _beats.get_beat_progress()

	var current_beat_progress: float = clampf(float(GM.current_beat) + beat_progress, 0.0, float(beat_limit))
	var failure_ratio: float = clampf(current_beat_progress / float(beat_limit), 0.0, 1.0)
	var fill_width: float = failure_track.size.x * failure_ratio
	failure_fill.size.x = maxf(fill_width, 0.0)

	var fill_color: Color = FAILURE_SAFE_FILL_COLOR.lerp(FAILURE_WARNING_FILL_COLOR, minf(failure_ratio / FAILURE_HIGH_RISK_THRESHOLD, 1.0))
	if failure_ratio >= FAILURE_HIGH_RISK_THRESHOLD:
		var danger_ratio: float = clampf((failure_ratio - FAILURE_HIGH_RISK_THRESHOLD) / (1.0 - FAILURE_HIGH_RISK_THRESHOLD), 0.0, 1.0)
		fill_color = FAILURE_WARNING_FILL_COLOR.lerp(FAILURE_DANGER_FILL_COLOR, danger_ratio)

	failure_fill.color = fill_color
	_failure_track_style.border_color = FAILURE_TRACK_BORDER_COLOR.lerp(FAILURE_DANGER_FILL_COLOR, clampf(maxf(failure_ratio - 0.6, 0.0) / 0.4, 0.0, 1.0))
	failure_label.text = "BEATS %d / %d" % [int(floor(current_beat_progress)), beat_limit]


func _update_control_pivot(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return

	control.pivot_offset = control.size * 0.5


func _on_goal_feedback_finished(goal_item: GoalItemView) -> void:
	goal_item.feedback_tween = null
	if goal_item.goal_card != null and is_instance_valid(goal_item.goal_card):
		goal_item.goal_card.scale = Vector2.ONE
	if goal_item.count_label != null and is_instance_valid(goal_item.count_label):
		goal_item.count_label.scale = Vector2.ONE
	if goal_item.count_label == null or not is_instance_valid(goal_item.count_label):
		return
	_apply_goal_feedback_strength(0.0, goal_item)


func _on_popup_tween_finished(popup_label: Label) -> void:
	if popup_label != null and is_instance_valid(popup_label):
		popup_label.queue_free()


func _on_beat_fired(_beat_index: int, _beat_time: float) -> void:
	_refresh_progress()
	_refresh_failure_progress()
