extends RefCounted

const GameplayExecutor = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"
)

var _executors: Dictionary[StringName, GameplayExecutor] = {}
const Contract = preload("res://Framework/Infrastructure/Implementation/Gameplay/executor_contract.gd")
var _descriptors: Dictionary[StringName, Dictionary] = {}
var _closed: bool = false


func register_executor(
	behavior_id: StringName,
	executor: Variant
) -> Dictionary:
	if _closed:
		return _failure("Executor registry is closed.")
	if String(behavior_id).strip_edges().is_empty():
		return _failure("Executor behavior ID cannot be empty.")
	if not executor is GameplayExecutor:
		return _failure("Executor must be a GameplayExecutor instance.")
	if _executors.has(behavior_id):
		return _failure("Executor behavior is already registered: %s" % behavior_id)
	var described := Contract.descriptor(behavior_id, executor.describe())
	if not described["ok"]:
		return described

	var executor_script: Script = executor.get_script()
	described["value"]["script_path"] = executor_script.resource_path

	_executors[behavior_id] = executor
	_descriptors[behavior_id] = described["value"]
	return {"ok": true, "value": true, "error": ""}


func resolve(behavior_id: StringName) -> Dictionary:
	if _closed:
		return _failure("Executor registry is closed.")
	if String(behavior_id).strip_edges().is_empty():
		return _failure("Executor behavior ID cannot be empty.")
	if not _executors.has(behavior_id):
		return _failure("Unknown executor behavior: %s" % behavior_id)

	return {"ok": true, "value": _executors[behavior_id], "error": ""}


func describe(behavior_id: StringName) -> Dictionary:
	var resolved := resolve(behavior_id)
	if not resolved["ok"]:
		return resolved
	return {"ok": true, "value": _descriptors[behavior_id].duplicate(true), "error": ""}


func catalogue() -> Dictionary:
	if _closed:
		return _failure("Executor registry is closed.")
	var entries: Array = []
	for id in get_ids():
		entries.append(_descriptors[id].duplicate(true))
	return {"ok": true, "value": entries, "error": ""}


func has_executor(behavior_id: StringName) -> bool:
	return not _closed and _executors.has(behavior_id)


func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = _executors.keys()
	ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return ids


func close() -> void:
	if _closed:
		return
	_closed = true
	_executors.clear()
	_descriptors.clear()


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
