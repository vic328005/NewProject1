extends TransportItem
class_name Product

const DEFAULT_PRODUCT_TYPE: String = CargoType.DEFAULT
const PRODUCT_TEXTURE_1: Texture2D = preload("res://assets/images/product_1.svg")
const PRODUCT_TEXTURE_2: Texture2D = preload("res://assets/images/product_2.svg")
const PRODUCT_TEXTURE_3: Texture2D = preload("res://assets/images/product_3.svg")

@export var product_type: String = DEFAULT_PRODUCT_TYPE:
	get:
		return _item_type
	set(value):
		_item_type = CargoType.normalize(value)
		_update_visual_state()


func is_product() -> bool:
	return true


func _update_visual_state() -> void:
	if _sprite == null:
		return

	_sprite.texture = get_texture_for_type(product_type)


static func get_texture_for_type(type_name: String) -> Texture2D:
	match type_name:
		CargoType.B:
			return PRODUCT_TEXTURE_2
		CargoType.C:
			return PRODUCT_TEXTURE_3
		_:
			return PRODUCT_TEXTURE_1
