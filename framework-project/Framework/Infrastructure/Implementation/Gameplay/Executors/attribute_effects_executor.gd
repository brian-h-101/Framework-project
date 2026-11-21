extends "res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"


func describe() -> Dictionary:
	return {"label": "Attribute Effects", "description": "Apply authored set and add effects to runtime attributes.",
		"supports_effects": true, "arguments": []}


func execute(
	context: ExecutionContext,
	definition: Dictionary,
	bindings: Dictionary,
	arguments: Dictionary
) -> Dictionary:
	if context == null:
		return _failure("Execution context is null.")
	if context.is_closed():
		return _failure("Execution context is closed.")
	var effects: Variant = definition.get("effects")
	if not effects is Array:
		return _failure("Action effects must be an Array.")
	var values: Array = []

	for effect: Variant in effects:
		if not effect is Dictionary:
			return _failure("Action effects must contain dictionaries.")
		for field in ["operation", "entity", "container", "value_from"]:
			if typeof(effect.get(field)) not in [TYPE_STRING, TYPE_STRING_NAME] or String(effect[field]).is_empty():
				return _failure("Action effect requires a nonempty text field: %s" % field)
		if not effect.get("path") is Array:
			return _failure("Action effect path must be an Array.")
		var role := StringName(effect["entity"])
		var argument_name := StringName(effect["value_from"])
		if not bindings.has(role):
			return _failure("Missing entity binding: %s" % role)
		if not arguments.has(argument_name):
			return _failure("Missing action argument: %s" % argument_name)
		if typeof(bindings[role]) != TYPE_INT:
			return _failure("Entity binding must be an integer ID: %s" % role)

		var result := context.execute_effect(
			StringName(effect["operation"]), bindings[role],
			StringName(effect["container"]), effect["path"], arguments[argument_name]
		)
		if not result["ok"]:
			return result
		values.append(result["value"])

	return {"ok": true, "value": values, "error": ""}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
