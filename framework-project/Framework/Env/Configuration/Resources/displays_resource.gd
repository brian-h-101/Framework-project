extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

@export var fields: Array[Dictionary] = []


func to_definition() -> Dictionary[StringName, Dictionary]:
	return named_entries(fields, "id")


func validation_error() -> String:
	var entry_validation := entry_error(fields, "id")
	if not entry_validation.is_empty():
		return entry_validation
	for field in fields:
		var error := attribute_error(field)
		if not error.is_empty():
			return error
		if not field.get("format") is String or String(field["format"]).count("%s") != 1:
			return "Display format must contain exactly one %s placeholder."
		if field.has("optional") and not field["optional"] is bool:
			return "The optional display flag must be boolean."
	return ""
