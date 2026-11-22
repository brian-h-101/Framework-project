extends RefCounted

const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")


static func execute(
	profile: Dictionary,
	intent: Dictionary,
	invoke_behavior: Callable,
	execute_action: Callable
) -> Dictionary:
	if not Intent.valid_axes(intent):
		return _failure("Movement intent requires finite lateral, forward and vertical axes.")

	var planar: bool = profile["legacy_planar"]
	var arguments := (
		{&"direction_x": intent[&"lateral"], &"direction_y": -intent[&"forward"]}
		if planar else intent
	)
	var result: Dictionary
	if profile["behavior_id"] != &"":
		var step_id: StringName = profile["velocity_step_id"]
		var report: Dictionary = invoke_behavior.call(profile["behavior_id"], step_id, arguments)
		if not report["ok"]:
			return report
		for step: Dictionary in report["value"]["steps"]:
			if step["id"] == step_id and step["status"] == "executed":
				result = step["result"]
				break
		if result.is_empty():
			return {"ok": true, "value": Intent.axes(), "error": ""}
	else:
		var speed: Dictionary = profile["speed"]
		arguments[&"speed_container"] = speed["container"]
		arguments[&"speed_path"] = speed["path"]
		result = execute_action.call(profile["action_id"], arguments)

	if not result["ok"]:
		return result
	var velocity: Variant = result["value"]
	if not velocity is Dictionary:
		return _failure("Movement requires a velocity dictionary.")
	if planar:
		if not Intent.is_finite_axis(velocity.get("x")) or not Intent.is_finite_axis(velocity.get("y")):
			return _failure("Planar movement requires finite x and y velocity.")
		velocity = Intent.axes(float(velocity["x"]), -float(velocity["y"]))
	elif not Intent.valid_axes(velocity):
		return _failure("Movement requires finite lateral, forward and vertical velocity.")
	return {"ok": true, "value": velocity, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
