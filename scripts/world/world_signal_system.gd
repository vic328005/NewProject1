class_name WorldSignalSystem
extends RefCounted

const TRIGGERED_SORTERS_KEY: StringName = &"sorters"
const TRIGGERED_PRESS_MACHINES_KEY: StringName = &"press_machines"
const TRIGGERED_PACKERS_KEY: StringName = &"packers"

var _world: World
var _active_signals: Array[SignalWave] = []
var _last_signal_emit_beat_index: int = -1


func _init(world: World) -> void:
	assert(world != null, "WorldSignalSystem requires a World instance.")
	_world = world


# 清空本关的信号运行态，配合 World 复用整体结构。
func clear() -> void:
	_active_signals.clear()
	_last_signal_emit_beat_index = -1


# 汇总当前所有信号波命中的设备，供本拍结算统一读取。
func collect_triggered_devices() -> Dictionary:
	return {
		TRIGGERED_SORTERS_KEY: _collect_triggered_sorters(),
		TRIGGERED_PRESS_MACHINES_KEY: _collect_triggered_press_machines(),
		TRIGGERED_PACKERS_KEY: _collect_triggered_packers(),
	}


# 推进当前拍的信号波前进并清理完成的波。
func advance_signals(beat_index: int) -> void:
	for index in range(_active_signals.size() - 1, -1, -1):
		var signal_wave: SignalWave = _active_signals[index]
		if signal_wave == null or not is_instance_valid(signal_wave):
			_active_signals.remove_at(index)
			continue

		signal_wave.advance(beat_index)
		if not signal_wave.is_finished():
			continue

		_active_signals.remove_at(index)
		signal_wave.remove_from_world()


# 按当前拍向全场信号塔尝试发射信号，单拍只允许一次发射。
func try_emit_for_current_beat() -> bool:
	var current_beat_index: int = 0
	var beats: BeatConductor = GM.beats
	if is_instance_valid(beats):
		current_beat_index = beats.get_current_beat_index()

	# 同一拍只允许发射一次，避免重复点击或多处调用叠加出额外信号波。
	if current_beat_index == _last_signal_emit_beat_index:
		return false

	var emitted: bool = false
	var signal_tower_cells: Dictionary = _world.signal_tower_layer.get_cells()
	for cell in signal_tower_cells.keys():
		var signal_tower: SignalTower = signal_tower_cells[cell] as SignalTower
		if signal_tower == null or not is_instance_valid(signal_tower):
			continue

		var signal_wave: SignalWave = signal_tower.create_signal_wave(current_beat_index)
		_active_signals.append(signal_wave)
		_world.add_level_content(signal_wave)
		emitted = true

	if not emitted:
		return false

	_last_signal_emit_beat_index = current_beat_index
	return true


# 收集当前生效信号波命中的分拣机，仅保留同一拍有效目标。
func _collect_triggered_sorters() -> Dictionary:
	var triggered_sorters: Dictionary = {}

	# 信号波按覆盖到的格子触发设备，设备类型各自独立收集。
	for signal_wave in _active_signals:
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var sorter: Sorter = _world.sorter_layer.get_cell(cell) as Sorter
			if sorter == null or not is_instance_valid(sorter):
				continue

			triggered_sorters[cell] = sorter

	return triggered_sorters


# 收集当前生效信号波命中的压机节点。
func _collect_triggered_press_machines() -> Dictionary:
	var triggered_press_machines: Dictionary = {}

	for signal_wave in _active_signals:
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var press_machine: PressMachine = _world.press_machine_layer.get_cell(cell) as PressMachine
			if press_machine == null or not is_instance_valid(press_machine):
				continue

			triggered_press_machines[cell] = press_machine

	return triggered_press_machines


# 收集当前生效信号波命中的打包机及当拍初始货物快照。
func _collect_triggered_packers() -> Dictionary:
	var triggered_packers: Dictionary = {}

	for signal_wave in _active_signals:
		if signal_wave == null or not is_instance_valid(signal_wave):
			continue

		var wave_cells: Array[Vector2i] = signal_wave.get_wave_cells()
		for cell in wave_cells:
			var packer: Packer = _world.packer_layer.get_cell(cell) as Packer
			if packer == null or not is_instance_valid(packer):
				continue

			# 这里记录信号命中当下的货物快照，避免同拍后续运输把新货送进来后被误打包。
			triggered_packers[cell] = {
				"packer": packer,
				"cargo": _world.cargo_layer.get_cell(cell) as Cargo,
			}

	return triggered_packers
