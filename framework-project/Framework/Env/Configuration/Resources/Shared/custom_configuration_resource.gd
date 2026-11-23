extends "res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd"

const ConfigurationType = preload("res://Framework/Env/Configuration/Resources/Shared/configuration_type_resource.gd")

@export var schema: ConfigurationType
@export var values: Dictionary = {}


func validation_error() -> String:
	if schema == null:
		return "Choose a Configuration Type."
	var error := schema.validation_error()
	if not error.is_empty():
		return error
	var fields := {}
	for field in schema.fields:
		fields[field["name"]] = field["type"]
	for key: Variant in values:
		if not key is String or not fields.has(key):
			return "Unknown configuration field: %s." % key
		if not ConfigurationType.matches_type(values[key], fields[key]):
			return "Configuration field '%s' must be %s." % [key, fields[key]]
	return ""


func to_definition() -> Dictionary:
	var result := {}
	for field in schema.fields:
		var field_name: String = field["name"]
		result[field_name] = values.get(field_name, field["default"])
	return result
