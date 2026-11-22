extends RefCounted

const Definition = preload("res://Framework/Infrastructure/Implementation/Gameplay/Behavior/behavior_definition.gd")
const Evaluator = preload("res://Framework/Infrastructure/Implementation/Gameplay/Behavior/behavior_evaluator.gd")

var _definitions: Dictionary = {}
var _bindings: Dictionary = {}
var _selected: Dictionary = {}
var _closed := false
var _evaluating := false

func define_behavior(data: Dictionary, describe: Callable) -> Dictionary:
	if _closed or _evaluating:
		return Definition.failure("Behavior system is closed or evaluating.")
	var error := Definition.validation_error(data, describe)
	if not error.is_empty():
		return Definition.failure(error)
	var id := StringName(data["id"])
	if _definitions.has(id):
		return Definition.failure("Duplicate Behavior ID: %s" % id)
	_definitions[id] = data.duplicate(true)
	return Definition.success(true)

func read_behavior(id: StringName) -> Dictionary:
	return Definition.failure("Unknown Behavior: %s" % id) if _closed or not _definitions.has(id) else Definition.success(_definitions[id].duplicate(true))

func bind(entity_id: int, id: StringName, enabled: bool = true) -> Dictionary:
	if _closed or _evaluating or not _definitions.has(id):
		return Definition.failure("Behavior is unknown, closed or evaluating.")
	if not _bindings.has(entity_id):
		_bindings[entity_id] = {}
	# A reloaded map must not reset a saved disabled state or cooldown.
	if not _bindings[entity_id].has(id):
		_bindings[entity_id][id] = {"enabled": enabled, "interval_remaining": _definitions[id]["configuration"]["interval_seconds"], "cooldown_remaining": 0.0}
	return Definition.success(true)

func bindings(entity_id: int) -> Dictionary:
	return Definition.failure("Behavior system is closed.") if _closed else Definition.success(_bindings.get(entity_id, {}).duplicate(true))

func set_enabled(entity_id: int, id: StringName, enabled: bool) -> Dictionary:
	if _closed or _evaluating or not _bindings.get(entity_id, {}).has(id):
		return Definition.failure("Behavior binding is unavailable.")
	_bindings[entity_id][id]["enabled"] = enabled
	return Definition.success(true)

func unbind(entity_id: int, id: StringName) -> Dictionary:
	if _closed or _evaluating:
		return Definition.failure("Behavior system is closed or evaluating.")
	if _bindings.has(entity_id):
		_bindings[entity_id].erase(id)
		if _bindings[entity_id].is_empty():
			_bindings.erase(entity_id)
	return Definition.success(true)

func select_target(actor: int, target: int) -> Dictionary:
	if _closed or _evaluating:
		return Definition.failure("Behavior system is closed or evaluating.")
	if target == 0:
		_selected.erase(actor)
	else:
		_selected[actor] = target
	return Definition.success(true)

func selected_target(actor: int) -> int:
	return 0 if _closed else int(_selected.get(actor, 0))

func invoke(id: StringName, actor: int, resolve: Callable, has_entity: Callable,
		connector: RefCounted, executor: RefCounted,
		step_id: StringName = &"", step_arguments: Dictionary = {}) -> Dictionary:
	if _closed or _evaluating or not resolve.is_valid() or not has_entity.is_valid():
		return Definition.failure("Behavior system is closed, evaluating or has no targeting service.")
	if not _bindings.get(actor, {}).has(id) or not _bindings[actor][id]["enabled"]:
		return Definition.failure("Behavior is not enabled for this entity: %s" % id)
	var state: Dictionary = _bindings[actor][id]
	if state["cooldown_remaining"] > 0:
		return Definition.failure("Behavior is cooling down: %s" % id)
	var definition: Dictionary = _definitions[id]
	var steps: Array = definition["steps"]
	if step_id != &"" or not step_arguments.is_empty():
		if definition["configuration"]["trigger"] != "manual":
			return Definition.failure("Only manual Behaviors accept invocation arguments.")

		steps = steps.duplicate(true)
		var step := _find_action_step(steps, step_id)
		if step.is_empty():
			return Definition.failure("Unknown Action step: %s" % step_id)

		var arguments: Dictionary = step["arguments"]
		for argument in step_arguments:
			if not arguments.has(argument):
				return Definition.failure("Action step '%s' has no argument '%s'." % [step_id, argument])
		arguments.merge(step_arguments.duplicate(true), true)

	_evaluating = true
	var target: Dictionary = resolve.call(actor, StringName(definition["configuration"]["targeting"]))
	var result: Dictionary
	if not target.get("ok", false):
		result = target
	elif not has_entity.call(actor) or typeof(target.get("value")) != TYPE_INT or not has_entity.call(target["value"]):
		result = Definition.failure("Behavior actor or target is unknown.")
	else:
		result = Evaluator.execute(steps, {&"actor": actor, &"target": target["value"]}, connector, executor,
			func() -> void: state["cooldown_remaining"] = definition["configuration"]["cooldown_seconds"])
	_evaluating = false
	return result

func _find_action_step(steps: Array, id: StringName) -> Dictionary:
	for step: Dictionary in steps:
		if step["kind"] == "group":
			var nested := _find_action_step(step["steps"], id)
			if not nested.is_empty():
				return nested
		elif StringName(step["id"]) == id:
			return step
	return {}

func emit_event(actor: int, event_id: StringName, invoke_behavior: Callable) -> Dictionary:
	if _closed or _evaluating or String(event_id).strip_edges().is_empty():
		return Definition.failure("Behavior event is invalid or unavailable.")
	var attempts := []
	for id in _sorted(_bindings.get(actor, {})):
		if _closed:
			return Definition.failure("Behavior system closed during event execution.")
		var config: Dictionary = _definitions[id]["configuration"]
		if config["trigger"] == "event" and StringName(config["event_id"]) == event_id and _bindings[actor][id]["enabled"]:
			attempts.append({"behavior_id": id, "result": invoke_behavior.call(id, actor)})
	return Definition.success(attempts)

func advance(delta: float, invoke_behavior: Callable) -> Dictionary:
	if _closed or _evaluating or not is_finite(delta) or delta < 0:
		return Definition.failure("Behavior time step must be finite and nonnegative, outside evaluation.")
	var attempts := []
	var actors: Array = _bindings.keys()
	actors.sort()
	for actor: int in actors:
		if _closed:
			return Definition.failure("Behavior system closed during update.")
		for id in _sorted(_bindings[actor]):
			if _closed:
				return Definition.failure("Behavior system closed during update.")
			var state: Dictionary = _bindings[actor][id]
			if not state["enabled"]:
				continue
			state["cooldown_remaining"] = maxf(0, state["cooldown_remaining"] - delta)
			var config: Dictionary = _definitions[id]["configuration"]
			if config["trigger"] != "interval":
				continue
			state["interval_remaining"] = maxf(0, state["interval_remaining"] - delta)
			if state["interval_remaining"] <= 0 and state["cooldown_remaining"] <= 0:
				state["interval_remaining"] = config["interval_seconds"]
				# At most one invocation per update; no catch-up burst after a long frame.
				attempts.append({"entity_id": actor, "behavior_id": id, "result": invoke_behavior.call(id, actor)})
	return Definition.success(attempts)

func snapshot(entity_ids: Dictionary[StringName, int]) -> Dictionary:
	if _closed or _evaluating:
		return Definition.failure("Cannot capture Behaviors while closed or evaluating.")
	var keys := {}
	for key in entity_ids:
		keys[entity_ids[key]] = key
	var output := {}
	for actor in _bindings:
		if not keys.has(actor):
			return Definition.failure("Behavior entity has no stable session key: %s" % actor)
		output[keys[actor]] = _bindings[actor].duplicate(true)
	return Definition.success(output)

func restore(records: Variant, entity_ids: Dictionary[StringName, int]) -> Dictionary:
	if _closed or _evaluating or not records is Dictionary:
		return Definition.failure("Saved Behaviors must be a dictionary, outside evaluation.")
	var prepared := {}
	for key in records:
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not entity_ids.has(StringName(key)) or not records[key] is Dictionary:
			return Definition.failure("Invalid saved Behavior entity key: %s" % str(key))
		var actor: int = entity_ids[StringName(key)]
		if prepared.has(actor):
			return Definition.failure("Duplicate saved Behavior entity key.")
		prepared[actor] = {}
		for raw_id in records[key]:
			if typeof(raw_id) not in [TYPE_STRING, TYPE_STRING_NAME] or not _definitions.has(StringName(raw_id)):
				return Definition.failure("Saved Behavior is not registered: %s" % str(raw_id))
			var id := StringName(raw_id)
			var state: Variant = records[key][raw_id]
			if prepared[actor].has(id) or not state is Dictionary or not state.get("enabled") is bool:
				return Definition.failure("Invalid saved Behavior state.")
			var config: Dictionary = _definitions[id]["configuration"]
			var copy := {"enabled": state["enabled"]}
			for timer in ["interval_remaining", "cooldown_remaining"]:
				if not Definition.number(state.get(timer)) or state[timer] < 0:
					return Definition.failure("Saved Behavior timers must be finite and nonnegative.")
				copy[timer] = minf(state[timer], config[timer.replace("_remaining", "_seconds")])
			prepared[actor][id] = copy
	_bindings = prepared
	_selected.clear() # Selection is transient presentation state, never a persisted runtime ID.
	return Definition.success(true)

func close() -> void:
	_closed = true
	_definitions.clear()
	_bindings.clear()
	_selected.clear()

func _sorted(values: Dictionary) -> Array:
	var ids: Array = values.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	return ids
