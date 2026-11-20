extends Resource


func validation_error() -> String:
	return ""


func to_definition() -> Dictionary:
	return {}


func read() -> Dictionary:
	var error := validation_error()
	if not error.is_empty():
		return {
			"ok": false,
			"value": null,
			"error": "%s: %s" % [resource_path if not resource_path.is_empty() else get_script().resource_path, error],
		}
	return {"ok": true, "value": to_definition(), "error": ""}


static func is_text(value: Variant) -> bool:
	return typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]


static func is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func entry_error(entries: Array[Dictionary], key_field: String) -> String:
	var names := {}
	for entry in entries:
		var name_value: Variant = entry.get(key_field)
		if not is_text(name_value) or String(name_value).is_empty():
			return "Each entry requires a nonempty %s." % key_field
		var entry_name := StringName(name_value)
		if names.has(entry_name):
			return "Duplicate %s: %s" % [key_field, entry_name]
		names[entry_name] = true
	return ""


static func named_entries(entries: Array[Dictionary], key_field: String) -> Dictionary[StringName, Dictionary]:
	var definition: Dictionary[StringName, Dictionary] = {}
	for entry in entries:
		var copied := entry.duplicate(true)
		copied.erase(key_field)
		definition[StringName(entry[key_field])] = copied
	return definition


static func attribute_error(definition: Dictionary) -> String:
	if not is_text(definition.get("container")) or String(definition["container"]).is_empty():
		return "An attribute requires a nonempty container name."
	var path: Variant = definition.get("path")
	if not path is Array or path.is_empty():
		return "An attribute requires a nonempty path array."
	for segment in path:
		if not is_text(segment) or String(segment).is_empty():
			return "Attribute path segments must be nonempty text."
	return ""
