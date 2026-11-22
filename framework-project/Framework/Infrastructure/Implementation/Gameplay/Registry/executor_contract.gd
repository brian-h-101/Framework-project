extends RefCounted

const TYPES = {"int": TYPE_INT, "float": TYPE_FLOAT, "String": TYPE_STRING,
	"StringName": TYPE_STRING_NAME, "bool": TYPE_BOOL, "Nil": TYPE_NIL,
	"Array": TYPE_ARRAY, "Dictionary": TYPE_DICTIONARY}


static func descriptor(behavior_id: StringName, supplied: Dictionary) -> Dictionary:
	if not supplied.get("label", "") is String or not supplied.get("description", "") is String or not supplied.get("supports_effects", false) is bool or not supplied.get("arguments", []) is Array:
		return failure("Executor '%s' has invalid authoring metadata." % behavior_id)
	var arguments: Array = []
	var names := {}
	for spec: Variant in supplied.get("arguments", []):
		if not spec is Dictionary or typeof(spec.get("name")) not in [TYPE_STRING, TYPE_STRING_NAME] or String(spec["name"]).strip_edges().is_empty() or not spec.get("required", true) is bool or not spec.get("allowed_types") is Array or spec["allowed_types"].is_empty():
			return failure("Executor '%s' requires named, typed argument specifications." % behavior_id)
		var name := String(spec["name"])
		if names.has(name):
			return failure("Executor '%s' declares duplicate argument: %s." % [behavior_id, name])
		names[name] = true
		var allowed: Array = []
		for type: Variant in spec["allowed_types"]:
			if not type is String or (type != "Variant" and not TYPES.has(type)) or allowed.has(type):
				return failure("Executor '%s' declares invalid argument types." % behavior_id)
			allowed.append(type)
		if allowed.has("Variant") and allowed.size() != 1:
			return failure("Variant must be the sole allowed type.")
		arguments.append(_spec(name, allowed, spec.get("required", true)))
	return success({"id": String(behavior_id), "label": supplied.get("label", "") if not String(supplied.get("label", "")).is_empty() else String(behavior_id),
		"description": supplied.get("description", ""), "supports_effects": supplied.get("supports_effects", false), "arguments": arguments})


static func argument_specs(description: Dictionary, definition: Dictionary) -> Dictionary:
	var effects: Variant = definition.get("effects", [])
	if not effects is Array:
		return failure("Action effects must be an Array.")
	if not description["supports_effects"] and not effects.is_empty():
		return failure("Behavior '%s' does not support attribute effects. Remove the effects before changing behavior." % description["id"])
	var specs: Array = description["arguments"].duplicate(true)
	for effect: Variant in effects:
		if not effect is Dictionary:
			return failure("Action effects must contain dictionaries.")
		var error := effect_error(effect)
		if not error.is_empty():
			return failure(error)
		var name := String(effect["value_from"])
		var allowed: Array = ["int", "float"] if String(effect["operation"]) == "add" else ["Variant"]
		var found := false
		for spec: Dictionary in specs:
			if spec["name"] != name:
				continue
			found = true
			var merged: Array = []
			if spec["allowed_types"] == ["Variant"]:
				merged = allowed
			elif allowed == ["Variant"]:
				merged = spec["allowed_types"].duplicate()
			else:
				for type in spec["allowed_types"]:
					if allowed.has(type):
						merged.append(type)
			if merged.is_empty():
				return failure("Executor metadata and effects disagree on argument: " + name)
			spec.merge(_spec(name, merged, true), true)
			break
		if not found:
			specs.append(_spec(name, allowed, true))
	return success(specs)


static func validate_arguments(description: Dictionary, definition: Dictionary, arguments: Dictionary) -> Dictionary:
	var prepared := argument_specs(description, definition)
	if not prepared["ok"]:
		return prepared
	for key in arguments:
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or String(key).is_empty():
			return failure("Interaction argument names must be nonempty text.")
	for spec: Dictionary in prepared["value"]:
		var name := StringName(spec["name"])
		if not arguments.has(name):
			if spec["required"]:
				return failure("Missing action argument: " + String(name))
			continue
		var value: Variant = arguments[name]
		var allowed: Array = spec["allowed_types"]
		if allowed == ["Variant"]:
			continue
		var valid := false
		for type: String in allowed:
			valid = valid or typeof(value) == TYPES[type]
		if not valid or (typeof(value) == TYPE_FLOAT and not is_finite(value)):
			return failure("Action argument '%s' requires a number." % name if spec["numeric"] else "Action argument '%s' requires: %s." % [name, ", ".join(allowed)])
	return success(true)


static func effect_error(effect: Dictionary) -> String:
	var error := address_error(effect)
	if not error.is_empty():
		return error
	if typeof(effect.get("operation")) not in [TYPE_STRING, TYPE_STRING_NAME] or String(effect["operation"]) not in ["set", "add"]:
		return "Effects require a supported operation: set or add."
	if typeof(effect.get("value_from")) not in [TYPE_STRING, TYPE_STRING_NAME] or String(effect["value_from"]).is_empty():
		return "Effects require a nonempty value_from argument name."
	return ""


static func address_error(definition: Dictionary) -> String:
	if typeof(definition.get("entity")) not in [TYPE_STRING, TYPE_STRING_NAME] or String(definition["entity"]) not in ["actor", "target"]:
		return "Gameplay addresses require an actor or target entity role."
	if typeof(definition.get("container")) not in [TYPE_STRING, TYPE_STRING_NAME] or String(definition["container"]).is_empty():
		return "Gameplay addresses require a nonempty container name."
	if not definition.get("path") is Array or definition["path"].is_empty():
		return "Gameplay addresses require a nonempty path array."
	for segment in definition["path"]:
		if typeof(segment) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
			return "Gameplay paths require String, StringName or integer segments."
	return ""


static func _spec(name: String, allowed: Array, required: bool) -> Dictionary:
	return {"name": name, "allowed_types": allowed, "required": required,
		"numeric": allowed.all(func(type: String) -> bool: return type in ["int", "float"])}


static func failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}


static func success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}
