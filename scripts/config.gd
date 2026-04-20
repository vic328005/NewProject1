class_name Config
extends RefCounted

var start_level_path: String = "res://levels/level01.json"
var selectable_level_paths: Array[String] = [
	"res://levels/level01.json",
	"res://levels/level02.json",
	"res://levels/level03.json",
	"res://levels/level04.json",
	"res://levels/level05.json",
	"res://levels/level06.json",
	"res://levels/level07.json",
]
var bpm: float = 160.0
var camera_scene_uid: String = "uid://b6k8wfglqo1sx"
var audio_scene_uid: String = "uid://c6xsief50rub2"
var cell_size: int = 64
