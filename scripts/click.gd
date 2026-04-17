extends Button

@export_node_path("Label") var count_label_path: NodePath

var _count := 0

func _ready() -> void:
	if not count_label_path.is_empty():
		var count_label := get_node_or_null(count_label_path) as Label
		if count_label != null:
			_count = int(count_label.text)

func _pressed() -> void:
	var count_label := get_node_or_null(count_label_path) as Label
	if count_label == null:
		return

	_count += 1
	count_label.text = str(_count)
