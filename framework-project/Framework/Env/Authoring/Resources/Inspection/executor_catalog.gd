extends RefCounted

const Setup = preload("res://Framework/Env/Setup/Bootstrap/game_setup.gd")
const SetupAPI = preload("res://Framework/Infrastructure/API/Runtime/game_setup.gd")
const Runtime = preload("res://Framework/Infrastructure/API/Runtime/game_runtime.gd")
const Core = preload("res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd")
const Shared = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Contract = preload("res://Framework/Infrastructure/Implementation/Gameplay/Registry/executor_contract.gd")

static var _cached: Dictionary = {}
static var _setup: SetupAPI
static var _browsing := false
static var _browse_cached: Dictionary = {}


static func begin_browse() -> Dictionary:
	_browsing = true
	return read()


static func end_browse() -> void:
	_browsing = false


static func _browse_read() -> Dictionary:
	if not _browse_cached.is_empty():
		return _browse_cached.duplicate(true)
	var setup: SetupAPI = _setup if _setup != null else Setup.new()
	var runtime := Runtime.new(Core.new(setup.get_clock_definition()))
	var registered := setup.register_executors(runtime)
	var catalogue := runtime.executor_catalogue() if registered["ok"] else registered
	runtime.close()
	if not catalogue["ok"]:
		return catalogue
	_browse_cached = Contract.success({"executors": catalogue["value"]})
	return _browse_cached.duplicate(true)


static func use_setup(setup: SetupAPI) -> void:
	_cached.clear()
	_browse_cached.clear()
	_setup = setup


static func refresh() -> Dictionary:
	_cached.clear()
	return read()


static func read() -> Dictionary:
	if _browsing:
		return _browse_read()
	if not _cached.is_empty():
		return _cached.duplicate(true)
	var snapshot := Shared.reference_snapshot()
	if not snapshot["ok"]:
		return snapshot
	var setup: SetupAPI = _setup if _setup != null else Setup.new()
	var runtime := Runtime.new(Core.new(setup.get_clock_definition()))
	var registered := setup.register_executors(runtime)
	if not registered["ok"]:
		runtime.close()
		return registered
	var catalog := runtime.executor_catalogue()
	runtime.close()
	if not catalog["ok"]:
		return catalog
	var checked := Shared.verify_snapshot(snapshot["value"])
	if not checked["ok"]:
		return checked
	_cached = Contract.success({"executors": catalog["value"], "executor_snapshot": snapshot["value"]})
	return _cached.duplicate(true)


static func describe(id: StringName) -> Dictionary:
	var catalog := read()
	if not catalog["ok"]:
		return catalog
	for entry: Dictionary in catalog["value"]["executors"]:
		if entry["id"] == String(id):
			return Contract.success(entry)
	return Contract.failure("Unknown executor behavior: " + String(id))


static func arguments_for(action: Resource) -> Dictionary:
	var description := describe(action.behavior_id)
	return Contract.argument_specs(description["value"], action.to_definition()) if description["ok"] else description


static func unchanged(expected: Variant, staged: String = "") -> Dictionary:
	if _browsing:
		return Contract.failure("Browsing metadata cannot authorize a Resource write.")
	var catalog := read()
	if not catalog["ok"]:
		return catalog
	if not expected is Dictionary or expected != catalog["value"]["executor_snapshot"]:
		return Contract.failure("Executor catalogue changed or was not inspected. Refresh and retry.")
	var checked := Shared.verify_snapshot(expected, staged)
	return checked if checked["ok"] else Contract.failure("Executor sources changed. Refresh and retry. " + checked["error"])


static func unchanged_at_stage(staged: String, expected: Dictionary) -> Dictionary:
	return unchanged(expected, staged)
