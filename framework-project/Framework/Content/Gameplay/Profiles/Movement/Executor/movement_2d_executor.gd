extends "res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"

const BEHAVIOR_ID: StringName = &"movement_2d"
const Movement = preload("res://Framework/Content/Gameplay/Profiles/Movement/Executor/movement_executor.gd")
const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")


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
	var calculated := Movement.calculate(
		context, bindings, arguments,
		Intent.axes(float(arguments[&"direction_x"]), -float(arguments[&"direction_y"]))
	)
	if calculated["ok"]:
		var velocity: Dictionary = calculated["value"]
		calculated["value"] = {"x": velocity[&"lateral"], "y": -velocity[&"forward"]}
	return calculated
