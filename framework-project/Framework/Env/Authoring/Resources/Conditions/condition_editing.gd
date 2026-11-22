extends RefCounted

const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Schema = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_schema.gd")

const ConditionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd"
)

const COMPARISON_OPERATORS = ["==", "!=", ">", ">=", "<", "<="]


static func set_comparison(
	condition_path: String,
	operator: String,
	value: Variant,
	message: String
) -> Dictionary:
	if (
		not condition_path.begins_with("res://")
		or condition_path.get_extension() != "tres"
		or condition_path.contains("\\")
		or condition_path.simplify_path() != condition_path
	):
		return _failure(
			"Expected a project-relative .tres path: %s"
			% condition_path
		)

	if not FileAccess.file_exists(condition_path):
		return _failure(
			"Resource file does not exist: %s" % condition_path
		)

	if operator not in COMPARISON_OPERATORS:
		return _failure(
			"Unsupported comparison operator: %s" % operator
		)

	if typeof(value) not in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		return _failure(
			"Condition comparison value must be a number."
		)

	if typeof(value) == TYPE_FLOAT and not is_finite(value):
		return _failure(
			"Condition comparison value must be finite."
		)

	var hashes := {condition_path: FileAccess.get_sha256(condition_path)}

	var loaded: Resource = ResourceLoader.load(
		condition_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded is ConditionResource):
		return _failure(
			"Expected a condition: %s" % condition_path
		)

	var condition: ConditionResource = loaded as ConditionResource

	if String(condition.id).is_empty():
		return _failure(
			"Condition ID cannot be empty: %s" % condition_path
		)

	if (
		not condition.requirement.has("operator")
		or not condition.requirement.has("value")
	):
		return _failure(
			"Condition must contain operator and value: %s"
			% condition_path
		)

	var updated_requirement: Dictionary = (
		condition.requirement.duplicate(true)
	)

	updated_requirement["operator"] = operator
	updated_requirement["value"] = value
	updated_requirement["message"] = message

	condition.requirement = updated_requirement
	var error := Schema.validate(condition)
	if not error.is_empty():
		return _failure(error)

	var saved := Files.save(condition_path, hashes, condition, Schema.snapshot)
	if not saved["ok"]:
		return saved

	return {
		"ok": true,
		"value": {
			"condition_path": condition_path,
			"operator": operator,
			"value": value,
			"message": message,
		},
		"error": "",
	}


static func get_comparison(condition_path: String) -> Dictionary:
	if (
		not condition_path.begins_with("res://")
		or condition_path.get_extension() != "tres"
		or condition_path.contains("\\")
		or condition_path.simplify_path() != condition_path
	):
		return _failure(
			"Expected a project-relative .tres path: %s"
			% condition_path
		)

	if not FileAccess.file_exists(condition_path):
		return _failure(
			"Resource file does not exist: %s" % condition_path
		)

	var loaded: Resource = ResourceLoader.load(
		condition_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded is ConditionResource):
		return _failure(
			"Expected a condition: %s" % condition_path
		)

	var condition: ConditionResource = loaded as ConditionResource

	if String(condition.id).is_empty():
		return _failure(
			"Condition ID cannot be empty: %s" % condition_path
		)

	var requirement: Dictionary = condition.requirement

	if (
		not requirement.has("operator")
		or not requirement.has("value")
	):
		return _failure(
			"Condition must contain operator and value: %s"
			% condition_path
		)

	var operator_value: Variant = requirement["operator"]

	if typeof(operator_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure(
			"Condition operator must be text: %s" % condition_path
		)

	var operator: String = String(operator_value)

	if operator not in COMPARISON_OPERATORS:
		return _failure(
			"Unsupported comparison operator: %s" % operator
		)

	var value: Variant = requirement["value"]
	var value_type: String
	var value_text: String

	match typeof(value):
		TYPE_BOOL:
			value_type = "bool"
			value_text = "true" if value else "false"
		TYPE_INT:
			value_type = "int"
			value_text = String.num_int64(int(value))

		TYPE_FLOAT:
			if not is_finite(value):
				return _failure(
					"Condition comparison value must be finite."
				)

			value_type = "float"
			value_text = JSON.stringify(value, "", true, true)

		_:
			return _failure(
				"Condition comparison value must be a number."
			)

	var message_value: Variant = requirement.get("message", "")

	if typeof(message_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure(
			"Condition message must be text: %s" % condition_path
		)

	return {
		"ok": true,
		"value": {
			"condition_path": condition_path,
			"operator": operator,
			"value_type": value_type,
			"value_text": value_text,
			"message": String(message_value),
		},
		"error": "",
	}


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}
