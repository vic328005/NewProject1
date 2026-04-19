extends Node
class_name GameManager

const UI_MODULE_SCENE: PackedScene = preload("res://prefabs/ui/ui_module.tscn")
const FAILURE_BEAT_LIMIT: int = 60

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


func _init() -> void:
	_init_config()
	_ensure_event()
	_ensure_beats()
	_ensure_level_loader()
	_init_audio()
	_init_camera()
	_init_world()
	_init_ui()


func _ready() -> void:
	assert(is_instance_valid(beats), "BeatConductor must exist before GameManager._ready.")
	if not beats.beat_fired.is_connected(_on_beat_fired):
		beats.beat_fired.connect(_on_beat_fired)

	_show_main_menu()


func emit_event(event_name: StringName, payload: Variant = null) -> void:
	_ensure_event().emit_event(event_name, payload)


func start_game() -> void:
	assert(config != null, "Config must be initialized before starting the game.")
	assert(is_instance_valid(world), "World must exist before starting the game.")
	assert(is_instance_valid(beats), "BeatConductor must exist before starting the game.")
	assert(is_instance_valid(ui), "UI module must exist before starting the game.")

	_close_flow_panels()
	_close_runtime_ui()
	_clear_session()

	var level_data: LevelData = _ensure_level_loader().load_level_file_into_world(config.start_level_path, world)
	if level_data == null:
		push_error("Failed to load start level: %s" % config.start_level_path)
		_show_main_menu()
		return

	if world.get_total_recycler_required_count() <= 0:
		push_error("Level has no recycler goals: %s" % config.start_level_path)
		_show_main_menu()
		return

	current_beat = 0
	state = GameState.PLAYING

	beats.reset(level_data.beat_bpm)
	ui.open(UIDef.metronome_panel)
	beats.start()


func finish_game(success: bool) -> void:
	if state != GameState.PLAYING:
		return

	assert(is_instance_valid(beats), "BeatConductor must exist before finishing the game.")
	assert(is_instance_valid(ui), "UI module must exist before finishing the game.")

	state = GameState.RESULT
	beats.stop()
	_close_runtime_ui()
	_close_menu_panel()

	var panel: ResultPanel = ui.open(UIDef.result_panel) as ResultPanel
	assert(panel != null, "Result panel scene root is not a ResultPanel.")
	var total_required_count: int = world.get_total_recycler_required_count()
	var remaining_required_count: int = world.get_remaining_recycler_required_count()
	panel.configure(
		success,
		total_required_count - remaining_required_count,
		total_required_count,
		current_beat,
		FAILURE_BEAT_LIMIT
	)


func return_to_main_menu() -> void:
	_show_main_menu()


func quit_game() -> void:
	get_tree().quit()


func _init_config() -> void:
	config = Config.new()
	assert(config != null, "Failed to create Config.")


func _ensure_event() -> EventBus:
	if is_instance_valid(event):
		return event

	event = EventBus.new()
	event.name = "EventBus"
	add_child(event)
	return event


func _ensure_beats() -> BeatConductor:
	if is_instance_valid(beats):
		return beats

	assert(config != null, "Config must be initialized before beat setup.")

	beats = BeatConductor.new()
	beats.name = "BeatConductor"
	beats.bpm = config.bpm
	add_child(beats)
	return beats


func _ensure_level_loader() -> LevelLoader:
	if level_loader != null:
		return level_loader

	level_loader = LevelLoader.new()
	return level_loader


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

	beats.stop()
	_close_result_panel()
	_close_runtime_ui()
	_clear_session()
	state = GameState.MENU
	ui.open(UIDef.main_menu_panel)


func _clear_session() -> void:
	if is_instance_valid(world):
		world.clear_level_content()

	current_beat = 0


func _close_flow_panels() -> void:
	_close_menu_panel()
	_close_result_panel()


func _close_menu_panel() -> void:
	if not is_instance_valid(ui):
		return

	ui.close_info(UIDef.main_menu_panel)


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
	if current_beat >= FAILURE_BEAT_LIMIT:
		finish_game(false)
