extends SceneTree

const ExecutorRegistry = preload(
	"res://Framework/Infrastructure/API/Gameplay/executor_registry.gd"
)
const GameplayExecutor = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"
)
const ExecutionContext = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/execution_context.gd"
)

var _passed: bool = true


class ProbeExecutor extends GameplayExecutor:
	var calls: int = 0
	var received_context: ExecutionContext
	var received_definition: Dictionary = {}
	var received_bindings: Dictionary = {}
	var received_arguments: Dictionary = {}

	func execute(
		context: ExecutionContext,
		definition: Dictionary,
		bindings: Dictionary,
		arguments: Dictionary
	) -> Dictionary:
		calls += 1
		received_context = context
		received_definition = definition
		received_bindings = bindings
		received_arguments = arguments
		return {
			"ok": true,
			"value": {
				"actor": bindings[&"actor"],
				"target": bindings[&"target"],
				"amount": arguments[&"amount"],
			},
			"error": "",
		}


func _initialize() -> void:
	var registry := ExecutorRegistry.new()
	var probe := ProbeExecutor.new()
	var registered := registry.register_executor(&"probe", probe)
	_expect("Executor registered", (
		registered == {"ok": true, "value": true, "error": ""}
		and registry.has_executor(&"probe")
	))
	_expect("Registration does not execute behavior", probe.calls == 0)

	var resolved := registry.resolve(&"probe")
	if not _expect("Lookup returns the registered instance", (
		resolved["ok"] and resolved["value"] == probe
	)):
		registry.close()
		_finish()
		return
	_expect("Lookup does not execute behavior", probe.calls == 0)

	var duplicate := registry.register_executor(&"probe", ProbeExecutor.new())
	_expect("Duplicate registration preserves the original executor", (
		_is_failure(duplicate, "Executor behavior is already registered: probe")
		and registry.resolve(&"probe")["value"] == probe
		and probe.calls == 0
	))

	for empty_id: StringName in [&"", &"   "]:
		_expect("Empty behavior ID is rejected", (
			_is_failure(registry.register_executor(empty_id, probe), "Executor behavior ID cannot be empty.")
			and _is_failure(registry.resolve(empty_id), "Executor behavior ID cannot be empty.")
			and not registry.has_executor(empty_id)
		))

	for invalid: Variant in [null, RefCounted.new(), GameplayExecutor, "executor.gd", 42]:
		_expect("Invalid executor is rejected", (
			_is_failure(registry.register_executor(&"invalid", invalid), "Executor must be a GameplayExecutor instance.")
			and not registry.has_executor(&"invalid")
		))

	_expect("Unknown behavior is rejected without executing", (
		_is_failure(registry.resolve(&"missing"), "Unknown executor behavior: missing")
		and not registry.has_executor(&"missing")
		and probe.calls == 0
	))

	registry.register_executor(&"alpha", ProbeExecutor.new())
	registry.register_executor(&"zeta", ProbeExecutor.new())
	var ids := registry.get_ids()
	_expect("Behavior IDs are sorted", ids == [&"alpha", &"probe", &"zeta"])
	ids.clear()
	_expect("Editing the returned ID list preserves registrations", (
		registry.get_ids() == [&"alpha", &"probe", &"zeta"]
	))

	var context := ExecutionContext.new()
	var definition := {"id": &"probe_action", "behavior_id": &"probe"}
	var bindings := {&"actor": 11, &"target": 22}
	var arguments := {&"amount": -7}
	var selected: GameplayExecutor = resolved["value"]
	var executed := selected.execute(context, definition, bindings, arguments)
	_expect("Selected executor receives its complete execution input", (
		probe.calls == 1
		and probe.received_context == context
		and probe.received_definition == definition
		and probe.received_bindings == bindings
		and probe.received_arguments == arguments
	))
	_expect("Executor returns the standard result structure", (
		executed == {"ok": true, "value": {"actor": 11, "target": 22, "amount": -7}, "error": ""}
	))
	_expect("Base contract reports an unimplemented executor", (
		_is_failure(GameplayExecutor.new().execute(context, {}, {}, {}), "Gameplay executor execute() is not implemented.")
	))

	var other_registry := ExecutorRegistry.new()
	var other_probe := ProbeExecutor.new()
	_expect("Separate registries own independent registrations", (
		not other_registry.has_executor(&"probe")
		and other_registry.register_executor(&"probe", other_probe)["ok"]
		and other_registry.resolve(&"probe")["value"] == other_probe
		and other_probe != probe
		and registry.resolve(&"probe")["value"] == probe
	))

	registry.register_executor(&"temporary", ProbeExecutor.new())
	var released: WeakRef = weakref(registry.resolve(&"temporary")["value"])
	registry.close()
	registry.close()
	_expect("Closing twice clears registrations and releases owned references", (
		registry.get_ids().is_empty()
		and not registry.has_executor(&"probe")
		and released.get_ref() == null
	))
	_expect("Closed registry rejects registration and lookup", (
		_is_failure(registry.register_executor(&"later", probe), "Executor registry is closed.")
		and _is_failure(registry.resolve(&"probe"), "Executor registry is closed.")
	))
	_expect("Closing one registry preserves another registry", (
		other_registry.resolve(&"probe")["value"] == other_probe
	))
	other_registry.close()
	_finish()


func _is_failure(result: Dictionary, message: String) -> bool:
	return result == {"ok": false, "value": null, "error": message}


func _expect(label: String, condition: bool) -> bool:
	print("[executor-registry] ", label, ": ", condition)
	_passed = _passed and condition
	return condition


func _finish() -> void:
	print("[executor-registry] Checks passed: ", _passed)
	quit(0 if _passed else 1)
