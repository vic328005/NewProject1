extends TransportItem
class_name Cargo

const DEFAULT_CARGO_TYPE: String = CargoType.DEFAULT
const CARGO_TEXTURE_1: Texture2D = preload("res://assets/images/cargo_1.png")
const CARGO_TEXTURE_2: Texture2D = preload("res://assets/images/cargo_2.png")
const CARGO_TEXTURE_3: Texture2D = preload("res://assets/images/cargo_3.png")

@export var cargo_type: String = DEFAULT_CARGO_TYPE:
	get:
		return _item_type
	set(value):
		_item_type = CargoType.normalize(value)
		_update_visual_state()


func is_cargo() -> bool:
	return true


func _update_visual_state() -> void:
	if _sprite == null:
		return

	_sprite.texture = get_texture_for_type(cargo_type)


static func get_texture_for_type(type_name: String) -> Texture2D:
	match type_name:
		CargoType.B:
			return CARGO_TEXTURE_2
		CargoType.C:
			return CARGO_TEXTURE_3
		_:
			return CARGO_TEXTURE_1
