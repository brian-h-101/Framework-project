extends RefCounted

const SCALARS = ["int", "float", "String", "StringName", "bool", "Nil"]


static func parse(kind: String, text: String) -> Dictionary:
	match kind:
		"String":
			return success(text)
		"StringName":
			return success(StringName(text))
		"int", "index":
			var stripped := text.strip_edges()
			if not stripped.is_valid_int():
				return failure("Expected a valid integer value.")
			var magnitude := stripped.trim_prefix("-").trim_prefix("+").lstrip("0")
			var limit := "9223372036854775808" if stripped.begins_with("-") else "9223372036854775807"
			if magnitude.length() > limit.length() or (magnitude.length() == limit.length() and magnitude.casecmp_to(limit) > 0):
				return failure("Integer value is outside Godot's signed 64-bit range.")
			return success(stripped.to_int())
		"float":
			if not text.strip_edges().is_valid_float():
				return failure("Expected a valid floating-point value.")
			var normalized := text.strip_edges().to_lower().split("e")
			var exponent: int = 0
			if normalized.size() == 2:
				var parsed := parse("int", normalized[1])
				if not parsed["ok"]:
					return failure("Floating-point exponent is outside the supported range.")
				exponent = parsed["value"]
			var coefficient := normalized[0].trim_prefix("-").trim_prefix("+")
			var point := coefficient.find(".")
			var fractional_digits := coefficient.length() - point - 1 if point >= 0 else 0
			var digits := coefficient.replace(".", "").lstrip("0")
			if digits.is_empty():
				return success(-0.0 if text.strip_edges().begins_with("-") else 0.0)
			if exponent > 1000000 or exponent < -1000000:
				return failure("Floating-point exponent is outside the supported range.")
			exponent += digits.length() - fractional_digits - 1
			if exponent > 308:
				return failure("Floating-point values must be finite.")
			if exponent < -324:
				return success(-0.0 if text.strip_edges().begins_with("-") else 0.0)
			var scientific := ("-" if text.strip_edges().begins_with("-") else "") + digits[0] + "." + digits.substr(1) + "e" + str(exponent)
			var value := scientific.to_float()
			if not is_finite(value):
				return failure("Floating-point values must be finite.")
			return success(value)
		"bool":
			if text not in ["true", "false"]:
				return failure("Boolean values must be true or false.")
			return success(text == "true")
		"Nil":
			if text != "null":
				return failure("Null values must be represented as null.")
			return success(null)
		"Dictionary":
			if text == "{}":
				return success({})
		"Array":
			if text == "[]":
				return success([])
	return failure("Unsupported value type or collection literal: %s" % kind)


static func value_text(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value)
		TYPE_INT:
			return String.num_int64(value)
		TYPE_FLOAT:
			return JSON.stringify(value, "", true, true)
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
		TYPE_DICTIONARY, TYPE_ARRAY:
			return "%s entries" % value.size()
		TYPE_OBJECT:
			return "Resource reference" if value is Resource else "Object"
	return var_to_str(value)


static func segment(key: Variant, array_index: bool = false) -> Dictionary:
	var kind := "index" if array_index else type_string(typeof(key))
	if kind not in ["index", "String", "StringName", "int"]:
		kind = "unsupported"
	return {"kind": kind, "text": var_to_str(key) if kind == "unsupported" else value_text(key)}


static func key_for(parent: Variant, part: Dictionary, existing: bool = true) -> Dictionary:
	if not part.get("kind") is String or not part.get("text") is String:
		return failure("Paths require typed key segments.")
	var kind: String = part["kind"]
	if parent is Array:
		if kind != "index":
			return failure("Array paths require index segments.")
		var parsed := parse(kind, part["text"])
		if not parsed["ok"]:
			return parsed
		var index: int = parsed["value"]
		if index < 0 or index >= parent.size():
			return failure("Array index is out of range.")
		return parsed
	if not parent is Dictionary or kind not in ["String", "StringName", "int"]:
		return failure("Dictionary paths require String, StringName or integer keys.")
	var parsed := parse(kind, part["text"])
	if not parsed["ok"] or not existing:
		return parsed
	for key in parent:
		if typeof(key) == typeof(parsed["value"]) and key == parsed["value"]:
			return success(key)
	return failure("The selected dictionary key no longer exists with that type.")


static func locate(root: Dictionary, path: Array) -> Dictionary:
	var current: Variant = root
	if path.size() > 64:
		return failure("Attribute paths cannot exceed 64 segments.")
	for part in path:
		if not part is Dictionary:
			return failure("Paths require typed key segments.")
		var found := key_for(current, part)
		if not found["ok"]:
			return found
		current = current[found["value"]]
	return success(current)


static func accepts(parent: Variant, key: Variant, value: Variant) -> bool:
	if parent is Array:
		return _matches(parent.get_typed_builtin(), value)
	if parent is Dictionary:
		return _matches(parent.get_typed_key_builtin(), key) and _matches(parent.get_typed_value_builtin(), value)
	return false


static func _matches(expected: int, value: Variant) -> bool:
	return expected == TYPE_NIL or expected == typeof(value) or (expected == TYPE_OBJECT and value == null)


static func success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


static func failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
