extends Node2D
class_name SignalTower

# 默认信号传播步数，作为导出属性的初始值使用。
const DEFAULT_MAX_STEPS: int = 10
# 信号波场景，发射时会实例化出一个独立的信号波对象。
const SIGNAL_SCENE: PackedScene = preload("res://prefabs/signal_wave.tscn")

var max_steps: int = DEFAULT_MAX_STEPS:
	set(value):
		max_steps = maxi(value, 1)

# 当前所属的世界引用。
# 信号塔依赖 World 提供的网格换算和图层注册能力。
var _world: World
# 信号塔注册到信号塔图层后的格子坐标。
var _registered_cell: Vector2i
# 标记当前是否已经写入图层，避免重复注销或误删别人的占位。
var _is_registered_to_layer: bool = false


func _ready() -> void:
	# 进入场景树后再获取世界，确保自动加载和场景节点都已可用。
	_world = GM.world
	# 启动时立即把自己登记到信号塔图层，并把位置吸附到格子中心。
	_register_to_signal_tower_layer()
	_subscribe_metronome_hit()


func _exit_tree() -> void:
	_unsubscribe_metronome_hit()
	# 离开场景树时主动从图层移除，避免留下失效引用。
	_unregister_from_signal_tower_layer()


func create_signal_wave(current_beat_index: int) -> SignalWave:
	# 每次发射都创建新的信号波实例，避免复用状态。
	var signal_wave: SignalWave = SIGNAL_SCENE.instantiate() as SignalWave
	assert(signal_wave != null, "Failed to instantiate Signal scene.")
	# 信号波从当前已登记的格子发出，并携带当前拍点信息。
	signal_wave.setup(_world, _registered_cell, max_steps, current_beat_index)
	return signal_wave


func get_registered_cell() -> Vector2i:
	# 对外暴露信号塔最终登记到的格子，避免外部重复计算坐标。
	return _registered_cell


func _subscribe_metronome_hit() -> void:
	if not is_instance_valid(GM.event):
		return

	var listener: Callable = Callable(self, "_on_metronome_hit")
	if not GM.event.has_subscriber(EventDef.metronome_hit, listener):
		GM.event.subscribe(EventDef.metronome_hit, listener)


func _unsubscribe_metronome_hit() -> void:
	if not is_instance_valid(GM.event):
		return

	GM.event.unsubscribe(EventDef.metronome_hit, Callable(self, "_on_metronome_hit"))


func _on_metronome_hit(payload: Variant) -> void:
	if _world == null or not _is_registered_to_layer:
		return

	if not (payload is Dictionary):
		return

	var event_payload: Dictionary = payload
	if not event_payload.has("beat_index"):
		return

	var beat_index: int = int(event_payload["beat_index"])
	var signal_wave: SignalWave = create_signal_wave(beat_index)
	_world.add_level_content(signal_wave)


func _register_to_signal_tower_layer() -> void:
	if _world == null:
		# 没有世界时无法完成坐标换算和图层登记，直接跳过。
		return

	# 先把全局坐标转换为世界局部坐标，再映射到格子坐标。
	_registered_cell = _world.world_to_cell(_world.to_local(global_position))
	# 在信号塔图层中记录自己，供系统按格子查询信号塔。
	_world.signal_tower_layer.set_cell(_registered_cell, self)
	# 注册完成后把节点位置对齐到格子中心，保证显示和逻辑位置一致。
	global_position = _world.to_global(_world.cell_to_world(_registered_cell))
	_is_registered_to_layer = true


func _unregister_from_signal_tower_layer() -> void:
	if not _is_registered_to_layer or _world == null:
		# 未注册或世界已失效时，不需要继续清理。
		return

	if _world.signal_tower_layer.get_cell(_registered_cell) == self:
		# 只清理由自己占用的格子，避免误删后来者的注册结果。
		_world.signal_tower_layer.erase_cell(_registered_cell)

	# 无论图层里是否仍是自己，都要同步更新本地注册状态。
	_is_registered_to_layer = false
