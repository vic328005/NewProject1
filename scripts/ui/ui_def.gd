extends RefCounted
class_name UIDef

enum UIOpenPolicy {
	SINGLE,
	MULTI,
}

const METRONOME_PANEL_SCENE: PackedScene = preload("res://prefabs/ui/metronome_panel.tscn")

static var metronome_panel: UIInfo = UIInfo.new(
	&"metronome_panel",
	METRONOME_PANEL_SCENE,
	0,
	UIOpenPolicy.SINGLE
)
