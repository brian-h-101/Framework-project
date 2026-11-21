extends SceneTree

const Entry = preload("res://Framework/Infrastructure/API/Runtime/game_entry.gd")
const Setup = preload("res://Framework/Infrastructure/API/Runtime/game_setup.gd")
const GameRuntime = preload("res://Framework/Infrastructure/API/Runtime/game_runtime.gd")
const RuntimeCore = preload("res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd")
const GameplayExecutor = preload("res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd")
const ExecutionContext = preload("res://Framework/Infrastructure/API/Gameplay/Executors/execution_context.gd")
const ActionResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/action_resource.gd")
const EnvironmentSetup = preload("res://Framework/Env/Setup/game_setup.gd")
const Codec = preload("res://Framework/Infrastructure/API/Persistence/session_codec.gd")

var _passed: bool = true


class ProbeExecutor extends GameplayExecutor:
	var calls: int = 0
	var last_context: ExecutionContext

	func execute(context: ExecutionContext, _definition: Dictionary, bindings: Dictionary, arguments: Dictionary) -> Dictionary:
		calls += 1
		last_context = context
		var changed := context.execute_effect(&"add", bindings[&"target"], &"health", ["current"], arguments[&"amount"])
		return {"ok": true, "value": [changed["value"]], "error": ""} if changed["ok"] else changed


class TrackingSetup extends Setup:
	var mode: StringName = &"valid"
	var behavior: StringName = &"probe"
	var order: Array[StringName] = []
	var captured_runtime: GameRuntime
	var executor: ProbeExecutor
	var create_called: bool = false

	func register_executors(runtime: GameRuntime) -> Dictionary:
		captured_runtime = runtime
		order.append(&"executors")
		if mode == &"skip":
			return {"ok": true, "value": true, "error": ""}
		executor = ProbeExecutor.new()
		return runtime.register_executor(&"attribute_effects" if mode == &"duplicate" else &"probe", executor)

	func register_content(runtime: GameRuntime) -> Dictionary:
		order.append(&"content")
		var action := ActionResource.new()
		action.id = &"probe_action"
		action.behavior_id = behavior
		var registered := runtime.define_action(action.to_definition())
		if not registered["ok"]:
			return registered
		var containers: Dictionary[StringName, Dictionary] = {
			&"health": {"current": 100},
			&"interactions": {"available": [&"probe_interaction"]},
		}
		runtime.define_attributes(&"probe_entity", containers)
		runtime.define_interaction({"id": &"probe_interaction", "action": &"probe_action",
			"requirements": [], "arguments": {&"amount": -7}})
		return {"ok": true, "value": true, "error": ""}

	func create_entities(runtime: GameRuntime) -> Dictionary[StringName, int]:
		create_called = true
		order.append(&"entities")
		return {&"actor": runtime.spawn(&"probe_entity"), &"target": runtime.spawn(&"probe_entity")}


class TrackingEnvironmentSetup extends EnvironmentSetup:
	var captured_runtime: GameRuntime
	var create_called: bool = false

	func register_executors(runtime: GameRuntime) -> Dictionary:
		captured_runtime = runtime
		return super.register_executors(runtime)

	func create_entities(runtime: GameRuntime) -> Dictionary[StringName, int]:
		create_called = true
		return super.create_entities(runtime)


func _initialize() -> void:
	_check_registration()
	_check_startup_and_restore()
	_check_resource_failure()
	print("[executor-startup] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_registration() -> void:
	var runtime := GameRuntime.new(RuntimeCore.new())
	_expect("Built-in executor is available before content registration", runtime.get_executor_ids() == [&"attribute_effects"] and runtime.has_executor(&"attribute_effects"))
	var resource := ActionResource.new()
	resource.id = &"checked_action"
	resource.effects = [{"operation": &"add", "entity": &"target", "container": &"health", "path": ["current"], "value_from": &"amount"}]
	var record := resource.to_definition()
	_expect("Action Resources include their behavior identifier", record["behavior_id"] == &"attribute_effects")
	var accepted := runtime.define_action(record)
	_expect("Known behavior is accepted without executing it", accepted == {"ok": true, "value": true, "error": ""})
	var custom := ProbeExecutor.new()
	_expect("Custom executor registers through the public runtime API", runtime.register_executor(&"probe", custom)["ok"] and runtime.has_executor(&"probe") and custom.calls == 0)
	_expect("Duplicate executor cannot replace a built-in", not runtime.register_executor(&"attribute_effects", custom)["ok"])
	var invalid_records := [
		{}, {"id": 42, "behavior_id": &"attribute_effects"},
		{"id": &"checked_action"}, {"id": &"checked_action", "behavior_id": &""},
		{"id": &"checked_action", "behavior_id": 42},
		{"id": &"checked_action", "behavior_id": &"missing"},
	]
	for invalid: Dictionary in invalid_records:
		var rejected := runtime.define_action(invalid)
		_expect("Invalid action registration reports a structured failure", not rejected["ok"] and rejected["value"] == null and not String(rejected["error"]).is_empty())
	var containers: Dictionary[StringName, Dictionary] = {&"health": {"current": 100}, &"interactions": {"available": [&"checked_interaction"]}}
	runtime.define_attributes(&"checked_entity", containers)
	var actor := runtime.spawn(&"checked_entity")
	var target := runtime.spawn(&"checked_entity")
	runtime.define_interaction({"id": &"checked_interaction", "action": &"checked_action", "arguments": {&"amount": -10}})
	_expect("Rejected replacements preserve the original action", runtime.interact(&"checked_interaction", actor, target)["value"] == [90])
	runtime.close()
	_expect("Closed runtime rejects action and executor registration", not runtime.define_action(record)["ok"] and not runtime.register_executor(&"later", custom)["ok"] and not runtime.has_executor(&"probe") and runtime.get_executor_ids().is_empty())


func _check_startup_and_restore() -> void:
	var entry := Entry.new()
	var setup := TrackingSetup.new()
	setup.mode = &"duplicate"
	var duplicate := entry.start(setup)
	_expect("Executor hook failures reach session startup", not duplicate["ok"] and String(duplicate["error"]).contains("already registered: attribute_effects"))
	_expect("Executor failures skip content and entity creation", setup.order == [&"executors"] and not setup.create_called)
	_expect("Executor failures clear and close the session", _stopped(entry) and not setup.captured_runtime.has_executor(&"attribute_effects") and not setup.captured_runtime.read_time()["ok"])

	setup = TrackingSetup.new()
	setup.mode = &"skip"
	var missing := entry.start(setup)
	_expect("Missing executors reject actions during startup", not missing["ok"] and missing["error"] == "Action 'probe_action': Unknown executor behavior: probe")
	_expect("Action failures occur before entity creation or world binding", setup.order == [&"executors", &"content"] and not setup.create_called and _stopped(entry))
	var rejected_runtime := setup.captured_runtime
	setup.mode = &"valid"
	setup.order.clear()
	var started := entry.start(setup)
	if not _expect("Retry succeeds on the same entry and setup", started["ok"]):
		entry.stop()
		return
	_expect("Executors register before content and entity creation", setup.order == [&"executors", &"content", &"entities"] and entry.runtime != rejected_runtime and setup.executor.calls == 0)
	_expect("Session action uses its registered custom behavior", entry.runtime.interact(&"probe_interaction", entry.entity_ids[&"actor"], entry.entity_ids[&"target"])["value"] == [93] and setup.executor.calls == 1)
	var saved := entry.snapshot_session()
	if not _expect("Custom-behavior session snapshot succeeds", saved["ok"]):
		entry.stop()
		return
	var encoded := Codec.encode(saved["value"])
	_expect("Session snapshots contain serializable gameplay data", encoded["ok"])
	var previous_context := setup.executor.last_context
	var previous_executor := setup.executor
	entry.stop()
	_expect("Stopping closes contexts retained by custom executors", previous_context.is_closed())

	var missing_restore_setup := TrackingSetup.new()
	missing_restore_setup.mode = &"skip"
	var rejected := entry.restore_session(missing_restore_setup, saved["value"])
	_expect("Restoration validates executors before restoring entities", not rejected["ok"] and not missing_restore_setup.create_called and _stopped(entry))
	var receiving_setup := TrackingSetup.new()
	var restored := entry.restore_session(receiving_setup, saved["value"])
	if not _expect("Restoration registers custom executors again", restored["ok"]):
		entry.stop()
		return
	_expect("Restoration creates fresh executor instances without startup spawning", receiving_setup.executor != previous_executor and receiving_setup.order == [&"executors", &"content"] and not receiving_setup.create_called)
	_expect("Restored executor uses the restored gameplay state", entry.runtime.interact(&"probe_interaction", entry.entity_ids[&"actor"], entry.entity_ids[&"target"])["value"] == [86] and receiving_setup.executor.calls == 1 and receiving_setup.executor.last_context != previous_context)
	entry.stop()


func _check_resource_failure() -> void:
	var folder := "res://Framework/Content/Behavior/DiagnosticExecutors_" + Crypto.new().generate_random_bytes(8).hex_encode()
	if not _expect("Diagnostic content folder is unused", not DirAccess.dir_exists_absolute(folder) and not FileAccess.file_exists(folder)):
		return
	if not _expect("Diagnostic content folder created", DirAccess.make_dir_absolute(folder) == OK):
		return
	var path := folder.path_join("missing_executor.tres")
	var resource := ActionResource.new()
	resource.id = &"diagnostic_missing_executor"
	resource.behavior_id = &"diagnostic_unregistered_behavior"
	if ResourceSaver.save(resource, path) != OK:
		_expect("Diagnostic Action Resource saved", false)
		DirAccess.remove_absolute(folder)
		return
	var entry := Entry.new()
	var setup := TrackingEnvironmentSetup.new()
	var rejected := entry.start(setup)
	_expect("Authored unknown behavior reports its Resource path", not rejected["ok"] and String(rejected["error"]).contains(path) and String(rejected["error"]).contains("Unknown executor behavior: diagnostic_unregistered_behavior"))
	_expect("Authored registration failure leaves no partial session", _stopped(entry) and not setup.create_called and not setup.captured_runtime.has_executor(&"attribute_effects"))
	entry.stop()
	_expect("Temporary Action Resource removed", DirAccess.remove_absolute(path) == OK)
	var empty_path := folder.path_join("empty_behavior.tres")
	resource.id = &"diagnostic_empty_behavior"
	resource.behavior_id = &""
	if ResourceSaver.save(resource, empty_path) == OK:
		var empty_setup := TrackingEnvironmentSetup.new()
		var empty := entry.start(empty_setup)
		_expect("Authored empty behavior reports its Resource path", not empty["ok"] and String(empty["error"]).contains(empty_path) and String(empty["error"]).contains("Action behavior ID cannot be empty"))
		_expect("Empty behavior skips entity creation", not empty_setup.create_called and _stopped(entry))
		entry.stop()
		_expect("Empty-behavior fixture removed", DirAccess.remove_absolute(empty_path) == OK)
	else:
		_expect("Empty-behavior fixture saved", false)
	_expect("Temporary content folder removed", DirAccess.remove_absolute(folder) == OK)
	var restarted := entry.start(EnvironmentSetup.new())
	_expect("Normal startup succeeds after invalid content is removed", restarted["ok"])
	entry.stop()


func _stopped(entry: Entry) -> bool:
	return entry.runtime == null and entry.world_bridge == null and entry.entity_ids.is_empty()


func _expect(label: String, condition: bool) -> bool:
	print("[executor-startup] ", label, ": ", condition)
	_passed = _passed and condition
	return condition
