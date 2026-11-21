extends "res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"

const BEHAVIOR_ID: StringName = &"change_health"


func describe() -> Dictionary:
	return {
		"label": "Change Health",
		"description": "Add an amount to the target's current health.",
		"supports_effects": false,
		"arguments": [
			{
				"name": "amount",
				"allowed_types": ["int", "float"],
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
	var target_id: int = bindings[&"target"]

	return context.execute_effect(
		&"add",
		target_id,
		&"health",
		["current"],
		arguments[&"amount"]
	)