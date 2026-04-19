extends RefCounted
class_name UIDef

enum UIOpenPolicy {
	SINGLE,
	MULTI,
}

const MAIN_MENU_PANEL_SCENE: PackedScene = preload("res://prefabs/ui/main_menu_panel.tscn")
const METRONOME_PANEL_SCENE: PackedScene = preload("res://prefabs/ui/metronome_panel.tscn")
const RESULT_PANEL_SCENE: PackedScene = preload("res://prefabs/ui/result_panel.tscn")

static var main_menu_panel: UIInfo = UIInfo.new(
	&"main_menu_panel",
	MAIN_MENU_PANEL_SCENE,
	10,
	UIOpenPolicy.SINGLE
)

static var metronome_panel: UIInfo = UIInfo.new(
	&"metronome_panel",
	METRONOME_PANEL_SCENE,
	0,
	UIOpenPolicy.SINGLE
)

static var result_panel: UIInfo = UIInfo.new(
	&"result_panel",
	RESULT_PANEL_SCENE,
	20,
	UIOpenPolicy.SINGLE
)
