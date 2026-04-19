extends RefCounted
class_name UIDef

enum UIOpenPolicy {
	SINGLE,
	MULTI,
}

const DEMO_PANEL_SCENE: PackedScene = preload("res://prefabs/ui/demo_panel.tscn")

static var demo_panel: UIInfo = UIInfo.new(
	&"demo_panel",
	DEMO_PANEL_SCENE,
	0,
	UIOpenPolicy.SINGLE
)
