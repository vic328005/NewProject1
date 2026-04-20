class_name Direction
extends RefCounted

enum Value {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

const NAMES: Array[String] = ["UP", "RIGHT", "DOWN", "LEFT"]


static func to_vector2i(direction: Value) -> Vector2i:
	match direction:
		Value.UP:
			return Vector2i.UP
		Value.RIGHT:
			return Vector2i.RIGHT
		Value.DOWN:
			return Vector2i.DOWN
		_:
			return Vector2i.LEFT


static func rotate_left(direction: Value) -> Value:
	return wrapi(int(direction) - 1, 0, 4) as Value


static func rotate_right(direction: Value) -> Value:
	return wrapi(int(direction) + 1, 0, 4) as Value


static func from_name(name: String) -> Value:
	var normalized_name: String = name.strip_edges().to_upper()
	match normalized_name:
		"UP":
			return Value.UP
		"RIGHT":
			return Value.RIGHT
		"DOWN":
			return Value.DOWN
		_:
			return Value.LEFT


static func is_valid_name(name: String) -> bool:
	return NAMES.has(name.strip_edges().to_upper())
