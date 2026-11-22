extends SceneTree

const Discovery = preload("res://Framework/Env/Setup/Discovery/executor_discovery.gd")
const ExecutorCatalogue = preload("res://Framework/Env/Authoring/Resources/Inspection/executor_catalog.gd")
const Runtime = preload("res://Framework/Infrastructure/API/Runtime/game_runtime.gd")
const Core = preload("res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd")
const MOVEMENT := "res://Framework/Content/Gameplay/Profiles/Movement/Executor/movement_2d_executor.gd"


func _initialize() -> void:
	var runtime := Runtime.new(Core.new())
	var registered := Discovery.register_all(runtime)
	var runtime_found: bool = registered["ok"] and registered["value"].get(&"movement_2d") == MOVEMENT
	var builtin_found := runtime.has_executor(&"attribute_effects")
	runtime.close()

	var editor := ExecutorCatalogue.read()
	var editor_found := false
	if editor["ok"]:
		for entry: Dictionary in editor["value"]["executors"]:
			if entry["id"] == "movement_2d":
				editor_found = entry["script_path"] == MOVEMENT
				break

	print("[executor-discovery] Runtime uses the Movement category: ", runtime_found)
	print("[executor-discovery] Built-in executor is registered: ", builtin_found)
	print("[executor-discovery] Editor reports the relocated script: ", editor_found)
	if not registered["ok"]:
		print(registered["error"])
	if not editor["ok"]:
		print(editor["error"])
	var passed := runtime_found and builtin_found and editor_found

	print("[executor-discovery] Checks passed: ", passed)
	quit(0 if passed else 1)
