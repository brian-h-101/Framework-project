extends RefCounted

const MAX_PREVIEW := 240
const MAX_INLINE_PACKED_ENTRIES := 16


static func describe(property_name: String, value: Variant, source_path: String) -> Dictionary:
	return {
		"name": property_name,
		"type": type_string(typeof(value)),
		"value": _preview(value),
		"source_path": source_path,
	}


static func _preview(value: Variant) -> String:
	match typeof(value):
		TYPE_OBJECT:
			if value is Resource:
				var path: String = value.resource_path
				if path.contains("::"):
					return _shorten("SubResource: " + path.get_slice("::", 1))
				return _shorten(path) if not path.is_empty() else value.get_class()
			return value.get_class() if is_instance_valid(value) else "null"
		TYPE_ARRAY, TYPE_DICTIONARY:
			return "%s entries" % value.size()
		TYPE_PACKED_BYTE_ARRAY:
			return "%s bytes" % value.size()
		TYPE_PACKED_STRING_ARRAY:
			# Strings can be large even when the packed array has very few entries.
			return "%s entries" % value.size()
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			if value.size() > MAX_INLINE_PACKED_ENTRIES:
				return "%s entries" % value.size()
		TYPE_STRING:
			if value.length() > MAX_PREVIEW:
				return _shorten(var_to_str(value.left(MAX_PREVIEW)))
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			if String(value).length() > MAX_PREVIEW:
				return _shorten(var_to_str(String(value).left(MAX_PREVIEW)))
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return type_string(typeof(value))
	return _shorten(var_to_str(value))


static func _shorten(value: String) -> String:
	# Keep tree descriptions on one line, including quoted multiline text.
	var single_line := value.replace("\r", "\\r").replace("\n", "\\n")
	return single_line if single_line.length() <= MAX_PREVIEW else single_line.left(MAX_PREVIEW - 3) + "..."
