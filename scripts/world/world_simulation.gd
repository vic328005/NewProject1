## 负责单个拍点内的世界结算。
class_name WorldSimulation
extends RefCounted

var _world: World


## 绑定要结算的世界实例。
func _init(world: World) -> void:
	assert(world != null, "WorldSimulation requires a World instance.")
	_world = world


## 执行一次完整拍点结算。
func resolve_beat(beat_index: int) -> void:
	_update_signal_waves(beat_index)


func _update_signal_waves(beat_index: int) -> void:
	# 当前先实现信号阶段：在一次遍历里推进并清理信号波。
	for node in _world.get_tree().get_nodes_in_group(SignalWave.GROUP_NAME):
		var signal_wave: SignalWave = node as SignalWave
		if signal_wave == null:
			continue

		if signal_wave.is_finished():
			signal_wave.remove_from_world()
			continue

		signal_wave.advance(beat_index)
		if signal_wave.is_finished():
			signal_wave.remove_from_world()
