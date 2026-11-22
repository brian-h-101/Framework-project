extends "res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"

const BEHAVIOR_ID := &"movement"
const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")
const VelocityCalculator = preload("res://Framework/Content/Universal/Movement/based/Execution/velocity_calculator.gd")


func describe() -> Dictionary:
	var arguments: Array[Dictionary] = []
	for axis: StringName in Intent.AXES:
		arguments.append({"name": String(axis), "allowed_types": ["int", "float"], "required": true})
	arguments.append({"name": "speed_container", "allowed_types": ["String", "StringName"], "required": true})
	arguments.append({"name": "speed_path", "allowed_types": ["Array"], "required": true})
	return {
		"label": "Movement",
		"description": "Calculate desired velocity in gameplay units from movement intent and runtime speed.",
		"supports_effects": false,
		"arguments": arguments,
	}


func execute(context: ExecutionContext, _definition: Dictionary, bindings: Dictionary, arguments: Dictionary) -> Dictionary:
	if not Intent.valid_axes(arguments):
		return _failure("Movement direction axes must be finite numbers.")
	return calculate(context, bindings, arguments, Intent.axes(
		float(arguments[&"lateral"]), float(arguments[&"forward"]), float(arguments[&"vertical"])
	))


static func calculate(context: ExecutionContext, bindings: Dictionary, arguments: Dictionary, direction: Dictionary) -> Dictionary:
	var speed_container := StringName(arguments[&"speed_container"])
	var speed_path: Array = arguments[&"speed_path"]
	if String(speed_container).strip_edges().is_empty() or speed_path.is_empty():
		return _failure("Movement requires a speed attribute address.")
	var speed := context.read_attribute(bindings[&"actor"], speed_container, speed_path)
	return VelocityCalculator.calculate(direction, speed["value"]) if speed["ok"] else speed


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
