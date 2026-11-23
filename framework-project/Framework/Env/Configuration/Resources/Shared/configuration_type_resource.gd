extends Resource

const FIELD_TYPES := ["int", "float", "bool", "String", "StringName"]
const MAX_FIELDS := 64

@export var id: StringName
@export var label: String
@export var fields: Array[Dictionary] = []


static func is_identifier(value: String) -> bool:
	return (
		value.length() <= 64 and value.is_valid_ascii_identifier()
		and value.left(1) in "abcdefghijklmnopqrstuvwxyz" and value == value.to_lower()
	)


static func matches_type(value: Variant, field_type: String) -> bool:
	return type_string(typeof(value)) == field_type and (field_type != "float" or is_finite(value))


func validation_error() -> String:
	if not is_identifier(String(id)) or id == &"movement":
		return "Use a lower-case Configuration Type ID starting with a letter. The ID movement is reserved."
	if label.strip_edges().is_empty() or label.length() > 100:
		return "Enter a Configuration Type label of 1–100 characters."
	if fields.is_empty() or fields.size() > MAX_FIELDS:
		return "A Configuration Type requires 1–%d fields." % MAX_FIELDS
	var names := {}
	for field in fields:
		var field_name: Variant = field.get("name")
		if not field_name is String or not is_identifier(field_name):
			return "Each field needs a lower-case name starting with a letter."
		if names.has(field_name):
			return "Duplicate configuration field: " + field_name
		names[field_name] = true
		var field_type: Variant = field.get("type")
		if field_type not in FIELD_TYPES:
			return "Unsupported type for configuration field: " + field_name
		if not matches_type(field.get("default"), field_type):
			return "Configuration field '%s' needs a default of type %s." % [field_name, field_type]
	return ""
