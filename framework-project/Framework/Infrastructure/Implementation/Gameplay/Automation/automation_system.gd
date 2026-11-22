extends RefCounted

# Session-owned definitions and activation state. No Nodes or Resources are retained.
var _definitions: Dictionary[StringName, Dictionary] = {}
var _bindings: Dictionary[int, Dictionary] = {}
var _closed := false
var _evaluating := false


func define_automation(definition: Dictionary, interaction_exists: Callable) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
	for field in ["id", "interaction", "trigger", "targeting"]:
		var value: Variant = definition.get(field)
		if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME] or String(value).strip_edges().is_empty():
			return _failure("Automation requires a nonempty text '%s' field." % field)
	var id := StringName(definition["id"])
	if _definitions.has(id):
		return _failure("Automation '%s' is already registered." % id)
	if not interaction_exists.call(StringName(definition["interaction"])):
		return _failure("Automation '%s' references an unregistered Interaction: %s." % [id, definition["interaction"]])
	if StringName(definition["trigger"]) != &"interval" or StringName(definition["targeting"]) != &"nearest":
		return _failure("Automation supports only interval triggers and nearest targeting.")
	for field in ["interval_seconds", "cooldown_seconds"]:
		var value: Variant = definition.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return _failure("Automation '%s': %s must be a finite number." % [id, field])
	if definition["interval_seconds"] <= 0 or definition["cooldown_seconds"] < 0:
		return _failure("Automation interval must be positive and cooldown nonnegative.")
	_definitions[id] = {
		"id": id, "interaction": StringName(definition["interaction"]),
		"trigger": &"interval", "targeting": &"nearest",
		"interval_seconds": float(definition["interval_seconds"]),
		"cooldown_seconds": float(definition["cooldown_seconds"]),
	}
	return _success(true)


func read_automation(id: StringName) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
	return _success(_definitions[id].duplicate(true)) if _definitions.has(id) else _failure("Unknown Automation: %s" % id)


func bind_automation(entity_id: int, id: StringName, enabled: bool = true) -> Dictionary:
	var checked := read_automation(id)
	if not checked["ok"]:
		return checked
	if _evaluating:
		return _failure("Cannot change Automation bindings during evaluation.")
	if not _bindings.has(entity_id):
		_bindings[entity_id] = {}
	# Reconfiguring a reloaded scene must not reset timers or re-enable a disabled rule.
	if not _bindings[entity_id].has(id):
		_bindings[entity_id][id] = {"enabled": enabled,
			"interval_remaining": _definitions[id]["interval_seconds"], "cooldown_remaining": 0.0}
	return read_bindings(entity_id)


func read_bindings(entity_id: int) -> Dictionary:
	return _failure("Game runtime is closed.") if _closed else _success(_bindings.get(entity_id, {}).duplicate(true))


func set_enabled(entity_id: int, id: StringName, enabled: bool) -> Dictionary:
	if _closed or _evaluating:
		return _failure("Automation system is closed or evaluating.")
	if not _bindings.get(entity_id, {}).has(id):
		return _failure("Automation is not bound to this entity.")
	_bindings[entity_id][id]["enabled"] = enabled
	return _success(true)


func unbind_automation(entity_id: int, id: StringName) -> Dictionary:
	if _closed or _evaluating:
		return _failure("Automation system is closed or evaluating.")
	if not _bindings.get(entity_id, {}).has(id):
		return _failure("Automation is not bound to this entity.")
	_bindings[entity_id].erase(id)
	if _bindings[entity_id].is_empty():
		_bindings.erase(entity_id)
	return _success(true)


func advance(delta: float, resolve_target: Callable, invoke: Callable) -> Dictionary:
	if _closed or _evaluating:
		return _failure("Automation system is closed or already evaluating.")
	if not is_finite(delta) or delta < 0.0 or not resolve_target.is_valid() or not invoke.is_valid():
		return _failure("Automation evaluation requires a finite nonnegative time step and valid callbacks.")
	_evaluating = true
	var attempts: Array[Dictionary] = []
	var entities := _bindings.keys()
	entities.sort()
	for entity_id: int in entities:
		var ids: Array = _bindings[entity_id].keys()
		ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
		for id: StringName in ids:
			if _closed:
				break
			var state: Dictionary = _bindings[entity_id][id]
			if not state["enabled"]:
				continue
			state["interval_remaining"] = maxf(0.0, state["interval_remaining"] - delta)
			state["cooldown_remaining"] = maxf(0.0, state["cooldown_remaining"] - delta)
			if state["interval_remaining"] > 0.0 or state["cooldown_remaining"] > 0.0:
				continue
			var definition: Dictionary = _definitions[id]
			# At most one attempt per binding per step; missed intervals never create bursts.
			state["interval_remaining"] = definition["interval_seconds"]
			var target: Variant = resolve_target.call(entity_id, definition["targeting"])
			if _closed:
				break
			if not target is Dictionary or target.get("ok") != true:
				continue
			var target_id: Variant = target.get("value")
			if not target_id is int or target_id <= 0 or target_id == entity_id:
				continue
			var result: Dictionary = invoke.call(definition["interaction"], entity_id, target_id)
			if result.get("ok", false):
				state["cooldown_remaining"] = definition["cooldown_seconds"]
			attempts.append({"entity_id": entity_id, "automation_id": id, "target_id": target_id, "result": result})
		if _closed:
			break
	_evaluating = false
	return _failure("Game runtime closed during Automation evaluation.") if _closed else _success(attempts)


func snapshot(entity_ids: Dictionary[StringName, int]) -> Dictionary:
	if _closed or _evaluating:
		return _failure("Automation system is closed or evaluating.")
	var keys_by_id := {}
	for key: StringName in entity_ids:
		keys_by_id[entity_ids[key]] = key
	var result := {}
	for entity_id: int in _bindings:
		if not keys_by_id.has(entity_id):
			return _failure("Activated entity %s has no stable session key." % entity_id)
		result[keys_by_id[entity_id]] = _bindings[entity_id].duplicate(true)
	return _success(result)


func restore(records: Variant, entity_ids: Dictionary[StringName, int]) -> Dictionary:
	if _closed or _evaluating:
		return _failure("Automation system is closed or evaluating.")
	if not records is Dictionary:
		return _failure("Saved Automations must be a dictionary.")
	var prepared: Dictionary[int, Dictionary] = {}
	for key in records:
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not entity_ids.has(StringName(key)) or not records[key] is Dictionary:
			return _failure("Saved Automation references an invalid entity key: %s." % str(key))
		var entity_id: int = entity_ids[StringName(key)]
		if prepared.has(entity_id):
			return _failure("Saved Automations contain duplicate entity keys.")
		prepared[entity_id] = {}
		for raw_id in records[key]:
			if typeof(raw_id) not in [TYPE_STRING, TYPE_STRING_NAME] or not _definitions.has(StringName(raw_id)):
				return _failure("Saved Automation is not registered: %s." % str(raw_id))
			var id := StringName(raw_id)
			var state: Variant = records[key][raw_id]
			if prepared[entity_id].has(id) or not state is Dictionary or not state.get("enabled") is bool:
				return _failure("Saved Automation activation state is invalid.")
			for timer in ["interval_remaining", "cooldown_remaining"]:
				var value: Variant = state.get(timer)
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or value < 0:
					return _failure("Saved Automation timer must be finite and nonnegative.")
			# Clamp to current authored durations if content changed since the save.
			prepared[entity_id][id] = {"enabled": state["enabled"],
				"interval_remaining": minf(float(state["interval_remaining"]), _definitions[id]["interval_seconds"]),
				"cooldown_remaining": minf(float(state["cooldown_remaining"]), _definitions[id]["cooldown_seconds"])}
	_bindings = prepared
	return _success(true)


func close() -> void:
	_closed = true
	_definitions.clear()
	_bindings.clear()


func _success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
