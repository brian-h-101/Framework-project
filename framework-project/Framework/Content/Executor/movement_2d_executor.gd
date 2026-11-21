extends "res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"

const BEHAVIOR_ID: StringName = &"movement_2d"


func describe() -> Dictionary:
	return {
		"label": "Movement 2D",
		"description": "Calculate desired velocity from direction and runtime speed.",
		"supports_effects": false,
		"arguments": [
			{
				"name": "direction_x",
				"allowed_types": ["int", "float"],
				"required": true,
			},
			{
				"name": "direction_y",
				"allowed_types": ["int", "float"],
				"required": true,
			},
			{
				"name": "speed_container",
				"allowed_types": ["String", "StringName"],
				"required": true,
			},
			{
				"name": "speed_path",
				"allowed_types": ["Array"],
				"required": true,
			},
		],
	}


func execute(
	context: ExecutionContext,
	_definition: Dictionary,
	bindings: Dictionary,
	arguments: Dictionary
) -> Dictionary:
	var x := float(arguments[&"direction_x"])
	var y := float(arguments[&"direction_y"])

	if absf(x) > 1.0 or absf(y) > 1.0:
		return _failure(
			"Movement direction axes must be between -1 and 1."
		)

	var speed_container := StringName(arguments[&"speed_container"])
	var speed_path: Array = arguments[&"speed_path"]

	if String(speed_container).strip_edges().is_empty() or speed_path.is_empty():
		return _failure("Movement requires a speed attribute address.")

	var speed := context.read_attribute(
		bindings[&"actor"],
		speed_container,
		speed_path
	)

	if not speed["ok"]:
		return speed

	if typeof(speed["value"]) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("Movement speed must be numeric.")

	var current_speed := float(speed["value"])

	if not is_finite(current_speed) or current_speed < 0.0:
		return _failure("Movement speed must be finite and nonnegative.")

	var length := sqrt(x * x + y * y)
	if length > 1.0:
		x /= length
		y /= length

	return {
		"ok": true,
		"value": {
			"x": x * current_speed,
			"y": y * current_speed,
		},
		"error": "",
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}