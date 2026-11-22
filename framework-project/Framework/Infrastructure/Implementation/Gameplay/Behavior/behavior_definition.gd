extends RefCounted

const Contract = preload("res://Framework/Infrastructure/Implementation/Gameplay/Registry/executor_contract.gd")

static func validation_error(data: Dictionary, describe: Callable = Callable()) -> String:
	if not _text(data.get("id")) or not data.get("configuration") is Dictionary:
		return "Behavior requires a nonempty ID and Configuration."
	var config: Dictionary = data["configuration"]
	if config.get("trigger") not in ["manual", "event", "interval"] or config.get("targeting") not in ["nearest", "selected", "self"]:
		return "Unsupported Behavior trigger or targeting rule."
	if config["trigger"] == "event" and not _text(config.get("event_id")):
		return "Event trigger requires a nonempty event ID."
	for key in ["interval_seconds", "cooldown_seconds"]:
		if not number(config.get(key)) or config[key] < 0 or (key == "interval_seconds" and config[key] == 0):
			return "Behavior interval must be positive and cooldown nonnegative, both finite."
	var storage_error := _storage_error(data, 0, {"count": 0})
	if not storage_error.is_empty():
		return storage_error
	if not data.get("steps") is Array:
		return "Behavior requires a Steps array."
	return _steps(data["steps"], {}, {"count": 0}, 0, describe)

static func _steps(steps: Array, ids: Dictionary, state: Dictionary, depth: int, describe: Callable) -> String:
	if depth > 32:
		return "Behavior exceeds 32 nested groups."
	for step in steps:
		state["count"] += 1
		if state["count"] > 1024 or not step is Dictionary or not _text(step.get("id")) or ids.has(String(step["id"])):
			return "Behavior steps require unique IDs, with at most 1024 steps."
		ids[String(step["id"])] = true
		if not step.get("label", "") is String or not step.get("requirements") is Array:
			return "Step labels must be text and requirements must be an array."
		for requirement in step["requirements"]:
			var error := requirement_error(requirement)
			if not error.is_empty():
				return "%s: %s" % [step["id"], error]
		if step.get("kind") == "group":
			if not step.get("steps") is Array:
				return "Group steps require a Steps array."
			var error := _steps(step["steps"], ids, state, depth + 1, describe)
			if not error.is_empty():
				return error
		elif step.get("kind") == "action":
			if not _text(step.get("executor_id")) or not step.get("arguments") is Dictionary or not step.get("effects", []) is Array:
				return "Action steps require an executor ID, arguments dictionary and effects array."
			if describe.is_valid():
				var description: Dictionary = describe.call(StringName(step["executor_id"]))
				if not description["ok"]:
					return description["error"]
				var checked := Contract.validate_arguments(description["value"], step, step["arguments"])
				if not checked["ok"]:
					return "%s: %s" % [step["id"], checked["error"]]
		else:
			return "Unknown Behavior step kind."
	return ""

static func requirement_error(value: Variant) -> String:
	if not value is Dictionary:
		return "Requirements must be dictionaries."
	var error := Contract.address_error(value)
	if not error.is_empty():
		return error
	if value.get("operator") not in ["==", "!=", ">", ">=", "<", "<="]:
		return "Unsupported comparison operator."
	if value.get("value") is bool:
		return "Boolean comparisons support only == and !=." if value["operator"] not in ["==", "!="] else ""
	return "Conditions require a finite number or boolean." if not number(value.get("value")) else ""

static func number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _text(value: Variant) -> bool:
	return typeof(value) in [TYPE_STRING, TYPE_STRING_NAME] and not String(value).strip_edges().is_empty()

static func success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}

static func failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}

static func _storage_error(value: Variant, depth: int, state: Dictionary) -> String:
	state["count"] += 1
	if depth > 96 or state["count"] > 50000:
		return "Behavior data exceeds its nesting or entry limit."
	if value is Dictionary:
		for key in value:
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
				return "Behavior dictionary keys must be text or integers."
			var error := _storage_error(value[key], depth + 1, state)
			if not error.is_empty():
				return error
	elif value is Array:
		for item in value:
			var error := _storage_error(item, depth + 1, state)
			if not error.is_empty():
				return error
	elif typeof(value) not in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME] or (value is float and not is_finite(value)):
		return "Behavior data must contain serializable scalar values and collections."
	return ""
