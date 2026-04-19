extends CanvasLayer
class_name UiModule

@onready var root: Control = $Root

var _single_panels: Dictionary[StringName, Control] = {}
var _panel_info_by_instance: Dictionary[Control, UIInfo] = {}


func _ready() -> void:
	assert(root != null, "UiModule requires a Root control.")


func show_module() -> void:
	visible = true


func hide_module() -> void:
	visible = false


func open(info: UIInfo) -> Control:
	assert(info != null, "UiModule.open requires a UIInfo.")

	if info.open_policy == UIDef.UIOpenPolicy.SINGLE:
		var existing_panel: Control = _get_single_panel(info.id)
		if existing_panel != null:
			return existing_panel

	var panel: Control = info.scene.instantiate() as Control
	assert(panel != null, "UI scene root must inherit Control: %s" % info.id)

	root.add_child(panel)
	panel.z_index = info.layer
	_panel_info_by_instance[panel] = info

	if info.open_policy == UIDef.UIOpenPolicy.SINGLE:
		_single_panels[info.id] = panel

	panel.tree_exited.connect(_on_panel_tree_exited.bind(panel))
	return panel


func close_info(info: UIInfo) -> bool:
	assert(info != null, "UiModule.close_info requires a UIInfo.")

	if info.open_policy == UIDef.UIOpenPolicy.SINGLE:
		var panel: Control = _get_single_panel(info.id)
		if panel == null:
			return false
		return close_instance(panel)

	var target_panel: Control = null
	for panel_key_variant: Variant in _panel_info_by_instance.keys():
		var panel_key: Control = panel_key_variant as Control
		if not is_instance_valid(panel_key):
			continue

		var panel_info: UIInfo = _panel_info_by_instance[panel_key]
		if panel_info.id == info.id:
			target_panel = panel_key
			break

	if target_panel == null:
		return false

	return close_instance(target_panel)


func close_instance(panel: Control) -> bool:
	if panel == null:
		return false

	if not _panel_info_by_instance.has(panel):
		return false

	_cleanup_panel(panel)
	panel.queue_free()
	return true


func _get_single_panel(id: StringName) -> Control:
	if not _single_panels.has(id):
		return null

	var panel: Control = _single_panels[id]
	if is_instance_valid(panel):
		return panel

	_single_panels.erase(id)
	return null


func _cleanup_panel(panel: Control) -> void:
	if not _panel_info_by_instance.has(panel):
		return

	var info: UIInfo = _panel_info_by_instance[panel]
	_panel_info_by_instance.erase(panel)

	if info.open_policy != UIDef.UIOpenPolicy.SINGLE:
		return

	if _single_panels.get(info.id) == panel:
		_single_panels.erase(info.id)


func _on_panel_tree_exited(panel: Control) -> void:
	_cleanup_panel(panel)
