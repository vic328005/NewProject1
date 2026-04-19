extends Node
class_name GameManager

const UI_MODULE_SCENE: PackedScene = preload("res://prefabs/ui/ui_module.tscn")

var config: Config
var event: EventBus
var beats: BeatConductor
var audio: AudioController = null
var camera: CameraController = null
var world: World = null
var ui: UiModule = null
var level_loader: LevelLoader


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
	_load_start_level()


func emit_event(event_name: StringName, payload: Variant = null) -> void:
	_ensure_event().emit_event(event_name, payload)


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


func _load_start_level() -> void:
	assert(config != null, "Config must be initialized before loading the start level.")

	var level_data: LevelData = _ensure_level_loader().load_level_file_into_world(config.start_level_path, world)
	if level_data == null:
		return

	assert(is_instance_valid(beats), "BeatConductor must exist before loading runtime UI.")
	beats.reset(level_data.beat_bpm)

	assert(is_instance_valid(ui), "UI module must exist before opening runtime panels.")
	ui.open(UIDef.metronome_panel)
