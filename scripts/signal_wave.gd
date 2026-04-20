extends Node2D
class_name SignalWave

# 波面填充色，用于在格子上绘制半透明覆盖。
const WAVE_FILL_COLOR: Color = Color(0.30, 0.69, 0.35, 0.38)
# 波面边框色，用于强调当前信号覆盖范围。
const WAVE_BORDER_COLOR: Color = Color(0.18, 0.41, 0.20, 0.9)
# 默认最大传播拍数。
const DEFAULT_MAX_STEPS: int = 10
# 信号波统一注册到场景树分组，便于结算阶段快速收集。
const GROUP_NAME: StringName = &"signal_waves"

# 最大传播半径，运行时始终保证至少为 1。
var max_steps: int = DEFAULT_MAX_STEPS:
	set(value):
		max_steps = maxi(value, 1)

# 所属世界，负责网格坐标换算和信号图层写入。
var _world: World
# 信号波的发射原点格子。
var _origin_cell: Vector2i
# 当前波面半径，表示已经扩张到第几圈。
var _wave_radius: int = 0
# 上一次推进时记录的拍点，用来避免同一拍重复推进。
var _last_wave_beat_index: int = -1
# 标记信号波是否已经结束。
var _is_finished: bool = false
# 当前波面覆盖到的全部格子。
var _wave_cells: Array[Vector2i] = []
# 当前写入 signal_layer 的格子记录，便于后续精确清理。
var _occupied_cells: Array[Vector2i] = []
# 是否已经参与 signal_layer 覆盖快照。
# 有些信号波可能已创建，但尚未进入正式结算覆盖层。
var _is_active_in_signal_layer: bool = false


func setup(world: World, origin_cell: Vector2i, signal_max_steps: int, current_beat_index: int) -> void:
	assert(world != null, "SignalWave requires a World instance.")
	# 初始化基础上下文，之后信号波的所有推进都依赖这些数据。
	_world = world
	_origin_cell = origin_cell
	max_steps = maxi(signal_max_steps, 1)
	# 节点位置固定在发射原点格子，绘制时再根据相对偏移展开。
	position = _world.cell_to_world(_origin_cell)
	# 创建后立即进入第一圈波面，因此初始半径为 1。
	_wave_radius = 1
	_last_wave_beat_index = current_beat_index
	_wave_cells = _build_wave_cells(_wave_radius)
	# 如果第一圈都没有有效格子，直接视为结束。
	_is_finished = _wave_cells.is_empty()
	queue_redraw()


func _enter_tree() -> void:
	add_to_group(GROUP_NAME)


func _exit_tree() -> void:
	# 离开场景树时清理自己在 signal_layer 里的占位，避免残留失效引用。
	_clear_signal_layer_occupancy()


func activate_in_signal_layer() -> void:
	if _world == null or _is_finished:
		return

	# 只有显式激活后，当前波面才会参与全局信号覆盖快照。
	_is_active_in_signal_layer = true
	_sync_signal_layer_occupancy()


func is_active_in_signal_layer() -> bool:
	return _is_active_in_signal_layer


func advance(current_beat_index: int) -> void:
	if _world == null or _is_finished:
		return

	if current_beat_index <= _last_wave_beat_index:
		# 同一拍或更早的拍点不重复推进，保证每拍最多扩张一次。
		return

	if _wave_radius >= max_steps:
		# 到达最大传播半径后立即结束，不再保留旧波面。
		_finish_wave()
		return

	var next_wave_radius: int = _wave_radius + 1
	_last_wave_beat_index = current_beat_index

	# 先更新半径，再重建整圈波面格子。
	_wave_radius = next_wave_radius
	_wave_cells = _build_wave_cells(_wave_radius)
	if _is_active_in_signal_layer:
		# 只有已激活的信号波才需要同步到共享图层。
		_sync_signal_layer_occupancy()
	queue_redraw()


func is_finished() -> bool:
	return _is_finished


func get_wave_cells() -> Array[Vector2i]:
	# 返回副本，避免外部直接改坏内部缓存。
	return _wave_cells.duplicate()


func covers_cell(cell: Vector2i) -> bool:
	# 供外部或图层恢复逻辑判断某个格子当前是否被此波面覆盖。
	return _wave_cells.has(cell)


func remove_from_world() -> void:
	# 先走统一结束流程，再真正释放节点。
	_finish_wave()
	queue_free()


func _draw() -> void:
	if _world == null or _wave_cells.is_empty():
		return

	# 以世界格子尺寸为基准，把当前波面逐格画成矩形覆盖。
	var cell_size: float = float(_world.main_layer.cell_size)
	var cell_extent: Vector2 = Vector2.ONE * cell_size

	for cell in _wave_cells:
		# 节点原点已经放在发射格，绘制时只需要计算相对偏移。
		var cell_origin: Vector2 = _cell_to_local_origin(cell, cell_size)
		var cell_rect: Rect2 = Rect2(cell_origin, cell_extent)
		draw_rect(cell_rect, WAVE_FILL_COLOR, true)
		draw_rect(cell_rect, WAVE_BORDER_COLOR, false, 2.0)


func _build_wave_cells(radius: int) -> Array[Vector2i]:
	# 当前实现生成的是“方形外圈”波面，并始终包含中心格。
	var cells: Array[Vector2i] = []
	var seen_cells: Dictionary = {}
	_append_wave_cell(_origin_cell, cells, seen_cells)

	var left: int = _origin_cell.x - radius
	var right: int = _origin_cell.x + radius
	var top: int = _origin_cell.y - radius
	var bottom: int = _origin_cell.y + radius

	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			if x != left and x != right and y != top and y != bottom:
				# 只保留边框格子，内部区域不属于当前这一圈波面。
				continue

			var cell: Vector2i = Vector2i(x, y)
			_append_wave_cell(cell, cells, seen_cells)

	return cells


func _append_wave_cell(cell: Vector2i, cells: Array[Vector2i], seen_cells: Dictionary) -> void:
	if seen_cells.has(cell):
		# 通过去重字典避免中心格或边角被重复加入。
		return

	seen_cells[cell] = true
	cells.append(cell)


func _finish_wave() -> void:
	if _is_finished:
		return

	# 结束后先停止参与图层覆盖，再清理占位和绘制缓存。
	_is_finished = true
	_is_active_in_signal_layer = false
	_clear_signal_layer_occupancy()
	_wave_cells.clear()
	queue_redraw()


func _sync_signal_layer_occupancy() -> void:
	if _world == null:
		return

	# 每次同步都先清掉自己上一拍写入的占位，再写入新波面。
	_clear_signal_layer_occupancy()
	for cell in _wave_cells:
		_world.signal_layer.set_cell(cell, self)
		_occupied_cells.append(cell)


func _clear_signal_layer_occupancy() -> void:
	if _world == null:
		# 世界已失效时只能清空本地记录，不能再访问图层。
		_occupied_cells.clear()
		return

	for cell in _occupied_cells:
		if _world.signal_layer.get_cell(cell) == self:
			# 只移除自己当前占着的格子，避免误删别的波面。
			_world.signal_layer.erase_cell(cell)

			var covering_signal_wave: SignalWave = _find_covering_signal_wave(cell)
			if covering_signal_wave != null:
				# 如果还有其他活跃波面覆盖该格，需要把它重新补回图层。
				_world.signal_layer.set_cell(cell, covering_signal_wave)

	_occupied_cells.clear()


func _find_covering_signal_wave(cell: Vector2i) -> SignalWave:
	if _world == null:
		return null

	# 通过专用分组查找其他仍活跃的信号波，避免扫描世界全部子节点。
	for node in _world.get_tree().get_nodes_in_group(GROUP_NAME):
		var signal_wave: SignalWave = node as SignalWave
		if signal_wave == null or signal_wave == self:
			continue

		if signal_wave._is_finished or not signal_wave._is_active_in_signal_layer:
			# 已结束或尚未激活的波面都不应参与覆盖恢复。
			continue

		if signal_wave.covers_cell(cell):
			return signal_wave

	return null


func _cell_to_local_origin(cell: Vector2i, cell_size: float) -> Vector2:
	# 把世界格子坐标转换为相对发射原点的本地绘制原点。
	var offset: Vector2i = cell - _origin_cell
	return Vector2(float(offset.x) * cell_size, float(offset.y) * cell_size)
