extends RefCounted

const Paths = preload(
	"res://Framework/Env/Setup/library_path_policy.gd"
)
const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const GameplayExecutor = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"
)

const ROOT: String = "res://Framework/Content/Executor"


static func register_all(runtime: GameRuntime) -> Dictionary:
	var listed := Paths.paths_in(ROOT, "gd")
	if not listed["ok"]:
		return listed

	var entries: Array[Dictionary] = []
	var sources: Dictionary[StringName, String] = {}

	for path: String in listed["value"]:
		if not path.get_file().ends_with("_executor.gd"):
			continue

		var executor_script := ResourceLoader.load(
			path, "Script"
		) as GDScript

		if executor_script == null:
			return _failure("Could not load executor script: " + path)

		if not executor_script.can_instantiate() or executor_script.is_abstract():
			return _failure("Executor cannot be instantiated: " + path)

		if not _inherits_executor(executor_script):
			return _failure("Executor must extend GameplayExecutor: " + path)

		var constants := executor_script.get_script_constant_map()
		var authored_id: Variant = constants.get("BEHAVIOR_ID")

		if typeof(authored_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _failure("Executor requires a text BEHAVIOR_ID: " + path)

		if String(authored_id).strip_edges().is_empty():
			return _failure("Executor BEHAVIOR_ID cannot be empty: " + path)

		var behavior_id := StringName(authored_id)

		if sources.has(behavior_id):
			return _failure(
				"Duplicate executor behavior '%s' in %s and %s."
				% [behavior_id, sources[behavior_id], path]
			)

		if runtime.has_executor(behavior_id):
			return _failure(
				"Executor behavior '%s' in %s is already registered."
				% [behavior_id, path]
			)

		sources[behavior_id] = path
		entries.append({
			"id": behavior_id,
			"script": executor_script,
			"path": path,
		})

	for entry: Dictionary in entries:
		var executor: Variant = entry["script"].new()
		var registered := runtime.register_executor(
			entry["id"], executor
		)

		if not registered["ok"]:
			return _failure(
				"Executor registration failed in %s: %s"
				% [entry["path"], registered["error"]]
			)

	return {"ok": true, "value": sources, "error": ""}


static func _inherits_executor(executor_script: Script) -> bool:
	var current: Script = executor_script

	while current != null:
		if current == GameplayExecutor:
			return true

		current = current.get_base_script()

	return false


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}