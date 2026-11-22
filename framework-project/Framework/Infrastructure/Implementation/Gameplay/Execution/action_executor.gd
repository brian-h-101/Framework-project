extends RefCounted

const ExecutorRegistry = preload(
	"res://Framework/Infrastructure/API/Gameplay/executor_registry.gd"
)
const ExecutionContext = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/execution_context.gd"
)
const GameplayExecutor = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"
)
# Direct legacy dispatch uses this default; runtime registration requires behavior_id.
const DEFAULT_BEHAVIOR: StringName = &"attribute_effects"
const Contract = preload("res://Framework/Infrastructure/Implementation/Gameplay/Registry/executor_contract.gd")

var _registry: ExecutorRegistry
var _context: ExecutionContext


func _init(
	registry: ExecutorRegistry,
	context: ExecutionContext
) -> void:
	_registry = registry
	_context = context


func execute(
	definition: Dictionary,
	bindings: Dictionary,
	arguments: Dictionary
) -> Dictionary:
	if _context == null:
		return _failure("Execution context is null.")
	if _context.is_closed():
		return _failure("Execution context is closed.")
	if _registry == null:
		return _failure("Action executor has no executor registry.")
	var behavior: Variant = definition.get("behavior_id", DEFAULT_BEHAVIOR)
	if typeof(behavior) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure("Action behavior_id must be text.")
	var behavior_id := StringName(behavior)
	var resolved := _registry.resolve(behavior_id)
	if not resolved["ok"]:
		return resolved
	var description := _registry.describe(behavior_id)
	var checked := Contract.validate_arguments(description["value"], definition, arguments)
	if not checked["ok"]:
		return checked

	var executor: GameplayExecutor = resolved["value"]
	var result := executor.execute(_context, definition, bindings, arguments)
	if typeof(result.get("ok")) != TYPE_BOOL or not result.has("value") or typeof(result.get("error")) != TYPE_STRING:
		return _failure("Executor '%s' returned an invalid result." % behavior_id)
	return result


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
