class_name CargoType
extends RefCounted

const A: String = "A"
const B: String = "B"
const C: String = "C"
const DEFAULT: String = A
const VALUES: Array[String] = [A, B, C]


static func normalize(value: Variant) -> String:
	var normalized_value: String = String(value).strip_edges().to_upper()
	return normalized_value if not normalized_value.is_empty() else DEFAULT


static func is_valid(value: Variant) -> bool:
	var normalized_value: String = String(value).strip_edges().to_upper()
	return not normalized_value.is_empty() and VALUES.has(normalized_value)
