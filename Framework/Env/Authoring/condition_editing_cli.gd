extends SceneTree

const ConditionEditing = preload(
	"res://Framework/Env/Authoring/condition_editing.gd"
)

const RESULT_PREFIX := "[condition-editing-result] "
const MAX_INT_MAGNITUDE := "9223372036854775807"
const MIN_INT_MAGNITUDE := "9223372036854775808"


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary

	if arguments.size() == 2 and arguments[0] == "get-comparison":
		result = ConditionEditing.get_comparison(arguments[1])
	elif arguments.size() == 6 and arguments[0] == "set-comparison":
		result = _set_comparison(arguments)
	else:
		result = _failure(
			"Expected get-comparison <condition_path> or "
			+ "set-comparison <condition_path> <operator> "
			+ "<int|float> <value_text> <message>."
		)

	print(RESULT_PREFIX, JSON.stringify(result))
	quit(0 if result["ok"] else 1)


func _set_comparison(arguments: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = _parse_number(
		arguments[3],
		arguments[4]
	)

	if not parsed["ok"]:
		return parsed

	var result: Dictionary = ConditionEditing.set_comparison(
		arguments[1],
		arguments[2],
		parsed["value"],
		arguments[5]
	)

	if not result["ok"]:
		return result

	var response: Dictionary = result["value"]
	response.erase("value")
	response["value_type"] = arguments[3]
	response["value_text"] = arguments[4].strip_edges()

	return result


func _parse_number(
	number_type: String,
	value_text: String
) -> Dictionary:
	var text: String = value_text.strip_edges()

	match number_type:
		"int":
			if not text.is_valid_int():
				return _failure(
					"Expected a valid integer value."
				)

			var magnitude: String = (
				text.trim_prefix("-").trim_prefix("+").lstrip("0")
			)

			if magnitude.is_empty():
				magnitude = "0"

			var limit: String = MAX_INT_MAGNITUDE
			if text.begins_with("-"):
				limit = MIN_INT_MAGNITUDE

			if (
				magnitude.length() > limit.length()
				or (
					magnitude.length() == limit.length()
					and magnitude.casecmp_to(limit) > 0
				)
			):
				return _failure(
					"Integer value is outside Godot's signed 64-bit range."
				)

			return {
				"ok": true,
				"value": text.to_int(),
				"error": "",
			}

		"float":
			if not text.is_valid_float():
				return _failure(
					"Expected a valid floating-point value."
				)

			var parsed_float: float = text.to_float()

			if not is_finite(parsed_float):
				return _failure(
					"Condition comparison value must be finite."
				)

			return {
				"ok": true,
				"value": parsed_float,
				"error": "",
			}

	return _failure(
		"Number type must be 'int' or 'float'."
	)


func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}
