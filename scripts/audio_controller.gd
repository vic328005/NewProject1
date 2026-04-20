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

const STREAM_SIGNAL_TOWER_FIRE: AudioStream = preload("res://assets/audios/signal_tower_fire.wav")
const STREAM_RECYCLER_DESTROY: AudioStream = preload("res://assets/audios/recycler_destroy.wav")
const STREAM_PRESS_MACHINE_COMPRESS: AudioStream = preload("res://assets/audios/press_machine_compress.wav")
const STREAM_PACKER_PACK: AudioStream = preload("res://assets/audios/packer_pack.wav")
const STREAM_PRODUCER_COUNTDOWN: AudioStream = preload("res://assets/audios/producer_countdown.wav")
const STREAM_PRODUCER_DROP: AudioStream = preload("res://assets/audios/producer_drop.wav")
const STREAM_RESULT_SUCCESS: AudioStream = preload("res://assets/audios/result_success.wav")
const STREAM_RESULT_FAIL: AudioStream = preload("res://assets/audios/result_fail.wav")

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
}


func _ready() -> void:
	assert(bgm_player != null, "AudioController requires a BgmPlayer.")


func play_sfx(key: StringName) -> void:
	var stream: AudioStream = _sfx_streams.get(key) as AudioStream
	if stream == null:
		push_warning("AudioController.play_sfx received an unknown key: %s" % String(key))
		return

	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(_on_sfx_player_finished.bind(player), CONNECT_ONE_SHOT)
	player.play()


func play_result(success: bool) -> void:
	if success:
		play_sfx(SFX_RESULT_SUCCESS)
		return

	play_sfx(SFX_RESULT_FAIL)


func _on_sfx_player_finished(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player):
		player.queue_free()
