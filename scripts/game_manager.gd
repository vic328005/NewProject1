extends Node
class_name GameManager

const UI_MODULE_SCENE: PackedScene = preload("res://prefabs/ui/ui_module.tscn")
# 达到这个拍数仍未完成关卡时，直接判定失败。
const DEFAULT_FAILURE_BEAT_LIMIT: int = LevelData.DEFAULT_FAILURE_BEAT_LIMIT

enum GameState {
	MENU,
	PLAYING,
	RESULT,
}

var config: Config
var event: EventBus
var beats: BeatConductor
var audio: AudioController = null
var camera: CameraController = null
var world: World = null
var ui: UiModule = null
var level_loader: LevelLoader
var state: int = GameState.MENU
var current_beat: int = 0
var current_level_failure_beat_limit: int = DEFAULT_FAILURE_BEAT_LIMIT
var current_level_path: String = ""


func _init() -> void:
	# 按依赖顺序完成核心模块初始化，避免后续生命周期里出现空引用。
	_init_config()
	_init_event()
	_init_beats()
	_init_level_loader()
	_init_audio()
	_init_camera()
	_init_world()
	_init_ui()


func _ready() -> void:
	assert(is_instance_valid(beats), "BeatConductor must exist before GameManager._ready.")
	if not beats.beat_fired.is_connected(_on_beat_fired):
		beats.beat_fired.connect(_on_beat_fired)

	# 启动后先进入主菜单，所有正式流程都从这里开始。
	_show_main_menu()


func start_game() -> void:
	_start_game_with_level_path(config.start_level_path)


func start_game_from_level_path(level_path: String) -> Dictionary:
	return _start_game_with_level_path(level_path)


func start_game_from_external_level(level_path: String) -> Dictionary:
	return start_game_from_level_path(level_path)


func restart_current_level() -> void:
	assert(config != null, "Config must be initialized before restarting the game.")
	assert(not current_level_path.is_empty(), "Current level path must exist before restarting the game.")
	_start_game_with_level_path(current_level_path)


func has_next_level() -> bool:
	return not _get_next_level_path().is_empty()


func start_next_level() -> void:
	var next_level_path: String = _get_next_level_path()
	assert(not next_level_path.is_empty(), "Next level path must exist before starting the next level.")
	_start_game_with_level_path(next_level_path)


func _start_game_with_level_path(level_path: String) -> Dictionary:
	assert(config != null, "Config must be initialized before starting the game.")
	assert(is_instance_valid(world), "World must exist before starting the game.")
	assert(is_instance_valid(beats), "BeatConductor must exist before starting the game.")
	assert(is_instance_valid(ui), "UI module must exist before starting the game.")

	# 开局前先停掉节拍并关闭运行时界面，只有真正加载成功后才收起主菜单。
	beats.stop()
	_close_result_panel()
	_close_runtime_ui()

	assert(level_loader != null, "LevelLoader must be initialized before starting the game.")
	var level_data: LevelData = level_loader.load_level_file_into_world(level_path, world)
	if level_data == null:
		_clear_session()
		state = GameState.MENU
		return _failure_start_result(_get_level_load_error_message(level_path))

	if world.get_total_recycler_required_count() <= 0:
		var error_message: String = "关卡缺少回收目标，无法开始游戏"
		push_error("%s：%s" % [error_message, level_path])
		_clear_session()
		state = GameState.MENU
		return _failure_start_result(error_message)

	_close_flow_panels()
	current_beat = 0
	current_level_failure_beat_limit = level_data.failure_beat_limit
	current_level_path = level_path
	state = GameState.PLAYING

	# 以关卡节奏参数重置节拍器，并打开运行中需要的 UI。
	if is_instance_valid(audio):
		audio.play_game_bgm()
	beats.reset(level_data.beat_bpm)
	ui.open(UIDef.metronome_panel)
	beats.start()
	return _success_start_result()


func finish_game(success: bool) -> void:
	if state != GameState.PLAYING:
		return

	assert(is_instance_valid(beats), "BeatConductor must exist before finishing the game.")
	assert(is_instance_valid(ui), "UI module must exist before finishing the game.")

	state = GameState.RESULT
	if is_instance_valid(audio):
		audio.play_result(success)
	beats.stop()
	_close_runtime_ui()
	_close_menu_panel()

	# 结果面板直接使用本局统计数据进行展示。
	var panel: ResultPanel = ui.open(UIDef.result_panel) as ResultPanel
	assert(panel != null, "Result panel scene root is not a ResultPanel.")
	var total_required_count: int = world.get_total_recycler_required_count()
	var remaining_required_count: int = world.get_remaining_recycler_required_count()
	panel.configure(
		success,
		total_required_count - remaining_required_count,
		total_required_count,
		current_beat,
		current_level_failure_beat_limit
	)


func return_to_main_menu() -> void:
	_show_main_menu()


func quit_game() -> void:
	get_tree().quit()


func _init_config() -> void:
	config = Config.new()
	assert(config != null, "Failed to create Config.")


func _init_event() -> void:
	event = EventBus.new()
	event.name = "EventBus"
	add_child(event)


func _init_beats() -> void:
	assert(config != null, "Config must be initialized before beat setup.")

	beats = BeatConductor.new()
	beats.name = "BeatConductor"
	beats.set_bpm(config.bpm)
	add_child(beats)


func _init_level_loader() -> void:
	level_loader = LevelLoader.new()


func _init_camera() -> void:
	assert(config != null, "Config must be initialized before camera setup.")

	var camera_scene: PackedScene = load(config.camera_scene_uid) as PackedScene
	assert(camera_scene != null, "Failed to load camera scene: %s" % config.camera_scene_uid)

	var camera_instance: CameraController = camera_scene.instantiate() as CameraController
	assert(camera_instance != null, "Camera scene root is not a CameraController: %s" % config.camera_scene_uid)

	camera_instance.name = "Camera"
	add_child(camera_instance)
	camera = camera_instance


func _init_audio() -> void:
	assert(config != null, "Config must be initialized before audio setup.")

	var audio_scene: PackedScene = load(config.audio_scene_uid) as PackedScene
	assert(audio_scene != null, "Failed to load audio scene: %s" % config.audio_scene_uid)

	var audio_instance: AudioController = audio_scene.instantiate() as AudioController
	assert(audio_instance != null, "Audio scene root is not an AudioController: %s" % config.audio_scene_uid)

	audio_instance.name = "Audio"
	add_child(audio_instance)
	audio = audio_instance


func _init_world() -> void:
	assert(config != null, "Config must be initialized before world setup.")

	var world_instance: World = World.new(config)
	world_instance.name = "World"
	add_child(world_instance)
	world = world_instance


func _init_ui() -> void:
	assert(UI_MODULE_SCENE != null, "Failed to load UI module scene.")

	var ui_instance: UiModule = UI_MODULE_SCENE.instantiate() as UiModule
	assert(ui_instance != null, "UI module scene root is not a UiModule.")

	ui_instance.name = "UI"
	add_child(ui_instance)
	ui = ui_instance


func _show_main_menu() -> void:
	assert(is_instance_valid(world), "World must exist before showing the main menu.")
	assert(is_instance_valid(beats), "BeatConductor must exist before showing the main menu.")
	assert(is_instance_valid(ui), "UI module must exist before showing the main menu.")

	# 返回主菜单时统一停掉节拍、关闭结果与运行时界面，并清空关卡内容。
	beats.stop()
	_close_level_select_panel()
	_close_result_panel()
	_close_runtime_ui()
	_clear_session()
	state = GameState.MENU
	if is_instance_valid(audio):
		audio.play_menu_bgm()
	ui.open(UIDef.main_menu_panel)


func _clear_session() -> void:
	if is_instance_valid(world):
		world.clear_level_content()

	current_beat = 0
	current_level_failure_beat_limit = DEFAULT_FAILURE_BEAT_LIMIT


func _close_flow_panels() -> void:
	_close_menu_panel()
	_close_level_select_panel()
	_close_result_panel()


func _close_menu_panel() -> void:
	if not is_instance_valid(ui):
		return

	ui.close_info(UIDef.main_menu_panel)


func _close_level_select_panel() -> void:
	if not is_instance_valid(ui):
		return

	ui.close_info(UIDef.level_select_panel)


func _close_result_panel() -> void:
	if not is_instance_valid(ui):
		return

	ui.close_info(UIDef.result_panel)


func _close_runtime_ui() -> void:
	if not is_instance_valid(ui):
		return

	ui.close_info(UIDef.metronome_panel)


func _on_beat_fired(beat_index: int, _beat_time: float) -> void:
	if state != GameState.PLAYING:
		return

	current_beat = beat_index
	# 超过失败拍数上限后，直接结束当前局。
	if current_beat >= current_level_failure_beat_limit:
		finish_game(false)


func _get_level_load_error_message(level_path: String) -> String:
	var error_message: String = level_loader.get_last_error_message()
	if not error_message.is_empty():
		return error_message

	return "加载关卡失败：%s" % level_path


func _success_start_result() -> Dictionary:
	return {
		"success": true,
		"message": "",
	}


func _failure_start_result(message: String) -> Dictionary:
	return {
		"success": false,
		"message": message,
	}


func _get_next_level_path() -> String:
	if config == null:
		return ""

	if current_level_path.is_empty():
		return ""

	var selectable_level_paths: Array[String] = config.selectable_level_paths
	var current_index: int = selectable_level_paths.find(current_level_path)
	if current_index == -1:
		return ""

	var next_index: int = current_index + 1
	if next_index >= selectable_level_paths.size():
		return ""

	return selectable_level_paths[next_index]
