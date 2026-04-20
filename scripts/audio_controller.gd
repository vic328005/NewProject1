extends Node2D
class_name AudioController

const SFX_SIGNAL_TOWER_FIRE: StringName = &"signal_tower_fire"
const SFX_RECYCLER_DESTROY: StringName = &"recycler_destroy"
const SFX_PRESS_MACHINE_COMPRESS: StringName = &"press_machine_compress"
const SFX_PACKER_PACK: StringName = &"packer_pack"
const SFX_PRODUCER_COUNTDOWN: StringName = &"producer_countdown"
const SFX_PRODUCER_DROP: StringName = &"producer_drop"
const SFX_RESULT_SUCCESS: StringName = &"result_success"
const SFX_RESULT_FAIL: StringName = &"result_fail"
const SFX_MENU_START: StringName = &"menu_start"
const SFX_MENU_EXIT: StringName = &"menu_exit"

const STREAM_MENU_BGM: AudioStream = preload("res://assets/audios/menu_bgm.wav")
const STREAM_GAME_BGM: AudioStream = preload("res://assets/audios/4.18.ogg")
const STREAM_SIGNAL_TOWER_FIRE: AudioStream = preload("res://assets/audios/signal_tower_fire.wav")
const STREAM_RECYCLER_DESTROY: AudioStream = preload("res://assets/audios/recycler_destroy.wav")
const STREAM_PRESS_MACHINE_COMPRESS: AudioStream = preload("res://assets/audios/press_machine_compress.wav")
const STREAM_PACKER_PACK: AudioStream = preload("res://assets/audios/packer_pack.wav")
const STREAM_PRODUCER_COUNTDOWN: AudioStream = preload("res://assets/audios/producer_countdown.wav")
const STREAM_PRODUCER_DROP: AudioStream = preload("res://assets/audios/producer_drop.wav")
const STREAM_RESULT_SUCCESS: AudioStream = preload("res://assets/audios/result_success.wav")
const STREAM_RESULT_FAIL: AudioStream = preload("res://assets/audios/result_fail.wav")
const STREAM_MENU_START: AudioStream = preload("res://assets/audios/start.wav")
const STREAM_MENU_EXIT: AudioStream = preload("res://assets/audios/exit.wav")

@export var bgm_player: AudioStreamPlayer

var _sfx_streams: Dictionary = {
	SFX_SIGNAL_TOWER_FIRE: STREAM_SIGNAL_TOWER_FIRE,
	SFX_RECYCLER_DESTROY: STREAM_RECYCLER_DESTROY,
	SFX_PRESS_MACHINE_COMPRESS: STREAM_PRESS_MACHINE_COMPRESS,
	SFX_PACKER_PACK: STREAM_PACKER_PACK,
	SFX_PRODUCER_COUNTDOWN: STREAM_PRODUCER_COUNTDOWN,
	SFX_PRODUCER_DROP: STREAM_PRODUCER_DROP,
	SFX_RESULT_SUCCESS: STREAM_RESULT_SUCCESS,
	SFX_RESULT_FAIL: STREAM_RESULT_FAIL,
	SFX_MENU_START: STREAM_MENU_START,
	SFX_MENU_EXIT: STREAM_MENU_EXIT,
}


func _ready() -> void:
	assert(bgm_player != null, "AudioController requires a BgmPlayer.")


func play_menu_bgm() -> void:
	_play_bgm(STREAM_MENU_BGM)


func play_game_bgm() -> void:
	_play_bgm(STREAM_GAME_BGM)


func play_sfx(key: StringName) -> AudioStreamPlayer:
	var stream: AudioStream = _sfx_streams.get(key) as AudioStream
	if stream == null:
		push_warning("AudioController.play_sfx received an unknown key: %s" % String(key))
		return null

	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(_on_sfx_player_finished.bind(player), CONNECT_ONE_SHOT)
	player.play()
	return player


func play_result(success: bool) -> void:
	if success:
		play_sfx(SFX_RESULT_SUCCESS)
		return

	play_sfx(SFX_RESULT_FAIL)


func _play_bgm(stream: AudioStream) -> void:
	assert(bgm_player != null, "AudioController requires a BgmPlayer.")
	assert(stream != null, "AudioController requires a valid BGM stream.")

	# 已在播放目标 BGM 时保持当前状态，避免重复切回时从头播放。
	if bgm_player.stream == stream and bgm_player.playing:
		return

	bgm_player.stream = stream
	bgm_player.play()


func _on_sfx_player_finished(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player):
		player.queue_free()
