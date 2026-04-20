extends Control
class_name MetronomePanel

# 轨道上总共显示的节拍刻度数量，中心刻度表示当前拍点。
const MARKER_COUNT: int = 11
# 中心刻度索引，用来把左右两侧的刻度围绕当前拍展开。
const CENTER_MARKER_INDEX: int = MARKER_COUNT / 2
# 轨道左右预留的内边距，避免边缘刻度贴边。
const TRACK_PADDING: float = 64.0
# 玩家输入命中/未命中反馈的持续时长。
const INPUT_FEEDBACK_DURATION: float = 0.16
# 命中窗口，只允许在拍点到来前的一段进度范围内判定为命中。
const HIT_WINDOW: float = 0.4
# 轨道与命中区、刻度的基础配色。
const TRACK_COLOR: Color = Color(0.07, 0.08, 0.11, 0.84)
const TRACK_BORDER_COLOR: Color = Color(0.9, 0.92, 0.98, 0.75)
const HIT_ZONE_COLOR: Color = Color(0.45, 0.36, 0.56, 0.32)
const HIT_ZONE_HIT_COLOR: Color = Color(0.2, 0.84, 0.46, 0.68)
const HIT_ZONE_MISS_COLOR: Color = Color(0.92, 0.3, 0.26, 0.62)
const MARKER_COLOR: Color = Color(0.93, 0.95, 0.98, 0.9)
const MARKER_HIT_COLOR: Color = Color(0.3, 0.96, 0.52, 0.98)
const MARKER_MISS_COLOR: Color = Color(1.0, 0.42, 0.34, 0.95)

enum FeedbackState {
	NONE,
	HIT,
	MISS,
}

# 主要 UI 节点引用。
# Track 负责整体容器，MarkerLayer 放动态刻度，HitZone 表示中心命中区域。
@onready var track: Panel = $BottomAnchor/Track
@onready var marker_layer: Control = $BottomAnchor/Track/MarkerLayer
@onready var hit_zone: Panel = $BottomAnchor/Track/HitZone

# 节拍驱动器，负责提供当前拍号和拍内进度。
var _beats: BeatConductor
# 轨道和命中区使用的样式对象，后续会直接改它们的颜色和边框。
var _track_style: StyleBoxFlat
var _hit_zone_style: StyleBoxFlat
# 动态生成的刻度节点和对应样式缓存。
var _markers: Array[Panel] = []
var _marker_styles: Array[StyleBoxFlat] = []
# 最近一次输入反馈状态，以及其剩余显示时间。
var _feedback_state: int = FeedbackState.NONE
var _feedback_time_remaining: float = 0.0
# 记录当前拍是否已经处理过一次输入，防止长按或重复事件同拍多次判定。
var _resolved_beat_index: int = -1


func _ready() -> void:
	assert(track != null, "MetronomePanel requires a Track node.")
	assert(marker_layer != null, "MetronomePanel requires a MarkerLayer node.")
	assert(hit_zone != null, "MetronomePanel requires a HitZone node.")

	# 这个面板只负责显示和输入判定，不拦截鼠标。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.clip_contents = true
	_beats = GM.beats
	assert(is_instance_valid(_beats), "MetronomePanel requires GM.beats.")

	# 启动时完成一次性的样式和刻度节点初始化。
	_setup_track_style()
	_setup_hit_zone_style()
	_create_markers()

	# 监听节拍触发，用来重置“本拍已处理输入”的标记。
	if not _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.connect(_on_beat_fired)

	_update_visuals()


func _exit_tree() -> void:
	# 离开场景树时断开信号，避免悬挂回调。
	if is_instance_valid(_beats) and _beats.beat_fired.is_connected(_on_beat_fired):
		_beats.beat_fired.disconnect(_on_beat_fired)


func _process(delta: float) -> void:
	# 每帧衰减输入反馈时间，结束后回到无反馈状态。
	if _feedback_time_remaining > 0.0:
		_feedback_time_remaining = maxf(_feedback_time_remaining - delta, 0.0)
		if _feedback_time_remaining == 0.0:
			_feedback_state = FeedbackState.NONE

	# 视觉内容完全由当前节拍和反馈状态推导，每帧统一刷新。
	_update_visuals()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_space_press(event):
		return

	if not is_instance_valid(_beats) or not is_instance_valid(GM.event):
		return

	var beat_index: int = _beats.get_current_beat_index()
	if _resolved_beat_index == beat_index:
		# 同一拍已经处理过输入时，直接吞掉后续重复事件。
		get_viewport().set_input_as_handled()
		return

	_resolved_beat_index = beat_index

	# 临时补丁：先不处理当前节拍手感问题，改为空格按下就直接发事件。
	# 同时继续保留“一拍只响应一次”的限制，后续再回到精确时机判定。
	_emit_metronome_hit(beat_index)
	if is_instance_valid(GM.audio):
		GM.audio.play_sfx(AudioController.SFX_SIGNAL_TOWER_FIRE)
	_trigger_feedback(FeedbackState.HIT)

	# 当前输入已经被节拍面板消费，不再继续传递。
	get_viewport().set_input_as_handled()


func _setup_track_style() -> void:
	# 轨道使用纯代码样式，避免依赖外部主题资源。
	_track_style = StyleBoxFlat.new()
	_track_style.bg_color = TRACK_COLOR
	_track_style.border_color = TRACK_BORDER_COLOR
	_track_style.border_width_left = 2
	_track_style.border_width_top = 2
	_track_style.border_width_right = 2
	_track_style.border_width_bottom = 2
	_track_style.corner_radius_top_left = 14
	_track_style.corner_radius_top_right = 14
	_track_style.corner_radius_bottom_right = 14
	_track_style.corner_radius_bottom_left = 14
	track.add_theme_stylebox_override("panel", _track_style)


func _setup_hit_zone_style() -> void:
	# 中心命中区样式同样在运行时构建，方便后续直接改色和缩放。
	_hit_zone_style = StyleBoxFlat.new()
	_hit_zone_style.bg_color = HIT_ZONE_COLOR
	_hit_zone_style.border_color = Color(0.92, 0.94, 0.98, 0.7)
	_hit_zone_style.border_width_left = 2
	_hit_zone_style.border_width_top = 2
	_hit_zone_style.border_width_right = 2
	_hit_zone_style.border_width_bottom = 2
	_hit_zone_style.corner_radius_top_left = 22
	_hit_zone_style.corner_radius_top_right = 22
	_hit_zone_style.corner_radius_bottom_right = 22
	_hit_zone_style.corner_radius_bottom_left = 22
	hit_zone.add_theme_stylebox_override("panel", _hit_zone_style)


func _create_markers() -> void:
	# 重新创建前先回收旧刻度，避免重复叠加。
	for marker: Panel in _markers:
		if is_instance_valid(marker):
			marker.queue_free()

	_markers.clear()
	_marker_styles.clear()

	for index in range(MARKER_COUNT):
		# 每个刻度都是一个独立 Panel，位置、尺寸和颜色都在 _update_visuals 中动态计算。
		var marker: Panel = Panel.new()
		var marker_style: StyleBoxFlat = StyleBoxFlat.new()
		marker.name = "Marker%d" % index
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_theme_stylebox_override("panel", marker_style)
		marker_layer.add_child(marker)
		_markers.append(marker)
		_marker_styles.append(marker_style)


func _update_visuals() -> void:
	if not is_instance_valid(_beats):
		return

	var track_size: Vector2 = track.size
	if track_size.x <= 0.0 or track_size.y <= 0.0:
		return

	var beat_progress: float = _beats.get_beat_progress()
	var center_x: float = track_size.x * 0.5
	var center_y: float = track_size.y * 0.5
	var spacing: float = (track_size.x - TRACK_PADDING * 2.0) / float(MARKER_COUNT - 1)
	var feedback_strength: float = _get_feedback_strength()

	for index in range(MARKER_COUNT):
		var marker: Panel = _markers[index]
		var marker_style: StyleBoxFlat = _marker_styles[index]
		# offset 表示该刻度相对当前拍的偏移量，负数在左边，正数在右边。
		var offset: int = index - CENTER_MARKER_INDEX
		# 随着 beat_progress 变化，刻度会朝中心流动。
		# 这里用“离最近整数拍中心的距离”控制当前位置和边缘淡出。
		var center_distance: float = absf(absf(float(offset)) - beat_progress)
		var edge_fade: float = clampf(1.0 - center_distance / float(CENTER_MARKER_INDEX + 1), 0.35, 1.0)
		# 命中/失误反馈只重点影响中心附近三个刻度。
		var is_feedback_focus: bool = abs(offset) <= 1 and feedback_strength > 0.0
	
		var marker_height: float = 28.0
		var marker_width: float = 10.0
		if is_feedback_focus:
			marker_height += 8.0 * feedback_strength
			marker_width += 2.0 * feedback_strength

		# 刻度沿横轴围绕中心移动，纵向始终居中。
		var direction: float = signf(float(offset))
		var marker_x: float = center_x + direction * center_distance * spacing - marker_width * 0.5
		var marker_y: float = center_y - marker_height * 0.5

		marker.position = Vector2(marker_x, marker_y)
		marker.size = Vector2(marker_width, marker_height)

		# 基础颜色统一，只在玩家按下后叠加命中/未命中反馈颜色。
		var fill_color: Color = MARKER_COLOR
		if is_feedback_focus:
			if _feedback_state == FeedbackState.HIT:
				fill_color = fill_color.lerp(MARKER_HIT_COLOR, feedback_strength)
			elif _feedback_state == FeedbackState.MISS:
				fill_color = fill_color.lerp(MARKER_MISS_COLOR, feedback_strength)
		fill_color.a *= edge_fade

		var border_color: Color = Color(fill_color.r, fill_color.g, fill_color.b, minf(fill_color.a + 0.1, 1.0))
		marker_style.bg_color = fill_color
		marker_style.border_color = border_color
		marker_style.border_width_left = 1
		marker_style.border_width_top = 1
		marker_style.border_width_right = 1
		marker_style.border_width_bottom = 1
		marker_style.corner_radius_top_left = int(round(marker_width * 0.5))
		marker_style.corner_radius_top_right = marker_style.corner_radius_top_left
		marker_style.corner_radius_bottom_right = marker_style.corner_radius_top_left
		marker_style.corner_radius_bottom_left = marker_style.corner_radius_top_left

	# 中心命中区只响应玩家按键反馈。
	_update_hit_zone(feedback_strength)


func _update_hit_zone(feedback_strength: float) -> void:
	# 平时命中区保持静止，只在玩家按下后显示命中/未命中反馈。
	var zone_scale: float = 1.0
	var zone_color: Color = HIT_ZONE_COLOR
	var border_color: Color = TRACK_BORDER_COLOR

	if feedback_strength > 0.0:
		if _feedback_state == FeedbackState.HIT:
			# 命中时稍微放大并偏向绿色。
			zone_scale += 0.12 * feedback_strength
			zone_color = zone_color.lerp(HIT_ZONE_HIT_COLOR, feedback_strength)
			border_color = border_color.lerp(MARKER_HIT_COLOR, feedback_strength)
		elif _feedback_state == FeedbackState.MISS:
			# 失误时略微收缩并偏向红色。
			zone_scale -= 0.08 * feedback_strength
			zone_color = zone_color.lerp(HIT_ZONE_MISS_COLOR, feedback_strength)
			border_color = border_color.lerp(MARKER_MISS_COLOR, feedback_strength)

	hit_zone.scale = Vector2.ONE * zone_scale
	hit_zone.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_hit_zone_style.bg_color = zone_color
	_hit_zone_style.border_color = border_color


func _get_feedback_strength() -> float:
	if _feedback_time_remaining <= 0.0:
		return 0.0

	# 输入反馈采用简单线性衰减，便于颜色和尺寸直接插值。
	return _feedback_time_remaining / INPUT_FEEDBACK_DURATION


func _trigger_feedback(feedback_state: int) -> void:
	# 每次输入结果都会刷新反馈状态和持续时间。
	_feedback_state = feedback_state
	_feedback_time_remaining = INPUT_FEEDBACK_DURATION


func _emit_metronome_hit(beat_index: int) -> void:
	var payload: Dictionary = {
		"beat_index": beat_index,
	}
	GM.event.emit_event(EventDef.metronome_hit, payload)


func _is_space_press(event: InputEvent) -> bool:
	# 只响应真正的空格按下，不处理抬起和键盘连发。
	if not (event is InputEventKey):
		return false

	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return false

	return key_event.keycode == KEY_SPACE or key_event.physical_keycode == KEY_SPACE


func _is_hit_timing(beat_progress: float) -> bool:
	# 只允许在拍点到来前的一小段窗口内命中。
	return beat_progress >= 1.0 - HIT_WINDOW


func _on_beat_fired(_beat_index: int, _beat_time: float) -> void:
	# 每次进入新拍时重置“本拍已处理输入”的标记。
	_resolved_beat_index = -1
