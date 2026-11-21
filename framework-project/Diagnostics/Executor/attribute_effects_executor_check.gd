extends SceneTree

const ExecutorRegistry = preload("res://Framework/Infrastructure/API/Gameplay/executor_registry.gd")
const GameplayExecutor = preload("res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd")
const ExecutionContext = preload("res://Framework/Infrastructure/API/Gameplay/Executors/execution_context.gd")
const ContextCore = preload("res://Framework/Infrastructure/Implementation/Gameplay/execution_context_core.gd")
const AttributeEffects = preload("res://Framework/Infrastructure/Implementation/Gameplay/Executors/attribute_effects_executor.gd")
const ActionExecutor = preload("res://Framework/Infrastructure/Implementation/Gameplay/action_executor.gd")
const EntityRegistry = preload("res://Framework/Infrastructure/Implementation/Entity/entity_registry.gd")
const EntityDefinition = preload("res://Framework/Infrastructure/Implementation/Entity/entity_definition.gd")
const Connector = preload("res://Framework/Infrastructure/Implementation/Entity/attribute_connector.gd")
const EffectExecutor = preload("res://Framework/Infrastructure/Implementation/Gameplay/effect_executor.gd")
const RuntimeCore = preload("res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd")
const GameRuntime = preload("res://Framework/Infrastructure/API/Runtime/game_runtime.gd")
const Action = preload("res://Diagnostics/Fixtures/GameplayResources/change_health.tres")
const Interaction = preload("res://Diagnostics/Fixtures/GameplayResources/strike.tres")

var _passed: bool = true


class ProbeExecutor extends GameplayExecutor:
	var received_context: ExecutionContext
	var received_id: StringName

	func execute(context: ExecutionContext, definition: Dictionary, bindings: Dictionary, arguments: Dictionary) -> Dictionary:
		received_context = context
		received_id = StringName(definition["id"])
		return context.write_attribute(bindings[&"target"], &"health", ["current"], arguments[&"amount"])


class InvalidResultExecutor extends GameplayExecutor:
	func execute(_context: ExecutionContext, _definition: Dictionary, _bindings: Dictionary, _arguments: Dictionary) -> Dictionary:
		return {"ok": "yes"}


func _initialize() -> void:
	_check_dispatch()
	_check_runtime()
	print("[executor-adapter] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_dispatch() -> void:
	var entities := EntityRegistry.new()
	var definition := EntityDefinition.new()
	definition.id = &"adapter_probe"
	definition.containers = {
		&"health": {"current": 100},
		&"flags": {"met_guard": false},
		&"interactions": {"available": []},
	}
	var actor := entities.create_entity(definition)
	var target := entities.create_entity(definition)
	var connector := Connector.new(entities)
	var context := ExecutionContext.new(ContextCore.new(connector, EffectExecutor.new(connector)))
	var registry := ExecutorRegistry.new()
	_expect("Attribute effects adapter registers", registry.register_executor(&"attribute_effects", AttributeEffects.new())["ok"])
	var dispatcher := ActionExecutor.new(registry, context)
	var bindings := {&"actor": actor, &"target": target}
	var writes: Array = []
	entities.attribute_written.connect(func(entity_id: int, container_id: StringName, attribute_name: StringName) -> void:
		writes.append([entity_id, container_id, attribute_name])
	)

	_expect("Context reads runtime attributes", context.read_attribute(target, &"health", ["current"])["value"] == 100)
	_expect("Context writes through the connector", context.write_attribute(target, &"health", ["current"], 95)["value"] == 95)
	_expect("Context executes existing add effects", context.execute_effect(&"add", target, &"health", ["current"], 5)["value"] == 100)
	_expect("Context executes existing set effects", context.execute_effect(&"set", actor, &"flags", ["met_guard"], true)["value"] == true)
	writes.clear()
	var action := Action.to_definition()
	var original := action.duplicate(true)
	var changed := dispatcher.execute(action, bindings, {&"amount": -10})
	_expect("Existing actions select attribute_effects and retain their result", changed == {"ok": true, "value": [90], "error": ""})
	_expect("Adapter writes notify listeners once", writes == [[target, &"health", &"current"]])
	_expect("Execution preserves the supplied definition", action == original)
	_expect("Direct actions do not consult interaction availability", context.read_attribute(actor, &"interactions", ["available"])["value"].is_empty() and changed["ok"])
	var explicit := {"id": &"explicit", "behavior_id": "attribute_effects", "effects": []}
	_expect("Explicit behavior IDs resolve independently of action IDs", dispatcher.execute(explicit, {}, {}) == {"ok": true, "value": [], "error": ""})

	var sequence := {"effects": [
		{"operation": &"set", "entity": &"target", "container": &"health", "path": ["current"], "value_from": &"amount"},
		{"operation": &"add", "entity": &"actor", "container": &"health", "path": ["current"], "value_from": &"delta"},
	]}
	var ordered := dispatcher.execute(sequence, bindings, {&"amount": 80, &"delta": -5})
	_expect("Multiple effects retain their order and role bindings", ordered["ok"] and ordered["value"] == [80, 95])
	var probe := ProbeExecutor.new()
	registry.register_executor(&"probe", probe)
	var custom := dispatcher.execute({"id": &"different_action_id", "behavior_id": &"probe"}, bindings, {&"amount": 79})
	_expect("Registry-selected custom executors receive the bound context", custom["ok"] and custom["value"] == 79 and probe.received_context == context and probe.received_id == &"different_action_id")
	registry.register_executor(&"invalid_result", InvalidResultExecutor.new())
	_expect("Invalid executor results are rejected", _failure_is(dispatcher.execute({"behavior_id": &"invalid_result"}, {}, {}), "Executor 'invalid_result' returned an invalid result."))

	writes.clear()
	var cases := [
		{"definition": {"behavior_id": &"missing"}, "bindings": bindings, "arguments": {}, "error": "Unknown executor behavior: missing"},
		{"definition": {"behavior_id": &""}, "bindings": bindings, "arguments": {}, "error": "Executor behavior ID cannot be empty."},
		{"definition": {"behavior_id": 42}, "bindings": bindings, "arguments": {}, "error": "Action behavior_id must be text."},
		{"definition": action, "bindings": bindings, "arguments": {}, "error": "Missing action argument: amount"},
		{"definition": action, "bindings": {}, "arguments": {&"amount": -10}, "error": "Missing entity binding: target"},
		{"definition": action, "bindings": bindings, "arguments": {&"amount": "bad"}, "error": "Action argument 'amount' requires a number."},
		{"definition": {}, "bindings": bindings, "arguments": {}, "error": "Action effects must be an Array."},
	]
	for specification in cases:
		var result := dispatcher.execute(specification["definition"], specification["bindings"], specification["arguments"])
		_expect(String(specification["error"]), _failure_is(result, specification["error"]))
	_expect("Rejected single effects and dispatch requests emit no writes", writes.is_empty() and context.read_attribute(target, &"health", ["current"])["value"] == 79)
	registry.close()
	_expect("Dispatch rejects a closed registry", _failure_is(dispatcher.execute(action, bindings, {&"amount": -10}), "Executor registry is closed."))
	context.close()
	context.close()
	_expect("Closed contexts reject reads, writes, effects, and dispatch", (
		_failure_is(context.read_attribute(target, &"health", ["current"]), "Execution context is closed.")
		and _failure_is(context.write_attribute(target, &"health", ["current"], -1), "Execution context is closed.")
		and _failure_is(context.execute_effect(&"set", target, &"health", ["current"], -1), "Execution context is closed.")
		and _failure_is(dispatcher.execute(action, bindings, {&"amount": -10}), "Execution context is closed.")
		and connector.read(connector.make_reference(target, &"health", ["current"]))["value"] == 79
	))
	var unbound := ExecutionContext.new()
	_expect("Unbound contexts report missing services", _failure_is(unbound.read_attribute(target, &"health", ["current"]), "Execution context has no attribute connector."))
	unbound.close()


func _make_runtime() -> Dictionary:
	var runtime := GameRuntime.new(RuntimeCore.new())
	var containers: Dictionary[StringName, Dictionary] = {
		&"health": {"current": 100},
		&"strength": {"current": 10},
		&"interactions": {"available": [&"strike"]},
	}
	runtime.define_attributes(&"adapter_probe", containers)
	runtime.define_action(Action.to_definition())
	runtime.define_interaction(Interaction.to_definition())
	return {"runtime": runtime, "actor": runtime.spawn(&"adapter_probe"),
		"target": runtime.spawn(&"adapter_probe", {&"interactions": {"available": []}})}


func _check_runtime() -> void:
	var first := _make_runtime()
	var runtime: GameRuntime = first["runtime"]
	var actor: int = first["actor"]
	var target: int = first["target"]
	var writes: Array = []
	runtime.attribute_written.connect(func(entity_id: int, container_id: StringName, attribute_name: StringName) -> void:
		writes.append([entity_id, container_id, attribute_name])
	)
	_expect("Runtime interactions reach the registered adapter", runtime.interact(&"strike", actor, target) == {"ok": true, "value": [90], "error": ""})
	_expect("Runtime notifications are preserved", writes == [[target, &"health", &"current"]])
	writes.clear()
	var rejected := runtime.interact(&"strike", target, actor)
	_expect("Interaction availability still gates execution", not rejected["ok"] and runtime.read_attribute(actor, &"health", ["current"])["value"] == 100 and writes.is_empty())
	runtime.write_attribute(actor, &"strength", ["current"], 9)
	writes.clear()
	var unmet := runtime.interact(&"strike", actor, target)
	_expect("Requirements still gate execution", not unmet["ok"] and runtime.read_attribute(target, &"health", ["current"])["value"] == 90 and writes.is_empty())
	runtime.write_attribute(actor, &"strength", ["current"], 10)
	_expect("Permitted interactions continue applying effects", runtime.interact(&"strike", actor, target)["value"] == [80])

	var second := _make_runtime()
	var other: GameRuntime = second["runtime"]
	_expect("Separate runtimes keep their gameplay state independent", other.read_attribute(second["target"], &"health", ["current"])["value"] == 100 and runtime.read_attribute(target, &"health", ["current"])["value"] == 80)
	runtime.close()
	runtime.close()
	_expect("Runtime shutdown rejects further interactions", _failure_is(runtime.interact(&"strike", actor, target), "Game runtime is closed."))
	_expect("Another runtime continues after the first closes", other.interact(&"strike", second["actor"], second["target"])["value"] == [90])
	other.close()


func _failure_is(result: Dictionary, error: String) -> bool:
	return result == {"ok": false, "value": null, "error": error}


func _expect(label: String, condition: bool) -> void:
	print("[executor-adapter] ", label, ": ", condition)
	_passed = _passed and condition
