extends SceneTree

const Entry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const Setup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)
const Interaction = preload(
	"res://Diagnostics/Fixtures/BehaviorEditing/visual_interaction.tres"
)


func _initialize() -> void:
	var entry := Entry.new()
	var passed := _run_check(entry)

	entry.stop()

	print("[content-executor] Checks passed: ", passed)
	quit(0 if passed else 1)


func _run_check(entry: Entry) -> bool:
	var started := entry.start(Setup.new())
	print("[content-executor] Session started: ", started)

	if not started["ok"]:
		return false

	var runtime = entry.runtime

	var action_registered: Dictionary = runtime.define_action(
		Interaction.action.to_definition()
	)
	print("[content-executor] Action registered: ", action_registered)

	if not action_registered["ok"]:
		return false

	var interaction_registered: Dictionary = runtime.define_interaction(
		Interaction.to_definition()
	)
	print("[content-executor] Interaction registered: ", interaction_registered)

	if not interaction_registered["ok"]:
		return false

	var containers: Dictionary[StringName, Dictionary] = {
		&"health": {"current": 100},
		&"strength": {"current": 20},
		&"interactions": {"available": [Interaction.id]},
	}

	runtime.define_attributes(&"content_executor_probe", containers)

	var actor_id: int = runtime.spawn(&"content_executor_probe")
	var target_id: int = runtime.spawn(&"content_executor_probe")

	var before: Dictionary = runtime.read_attribute(
		target_id, &"health", ["current"]
	)
	print("[content-executor] Target health before: ", before)

	var result: Dictionary = runtime.interact(
		Interaction.id, actor_id, target_id
	)
	print("[content-executor] Interaction result: ", result)

	var after: Dictionary = runtime.read_attribute(
		target_id, &"health", ["current"]
	)
	var actor_health: Dictionary = runtime.read_attribute(
		actor_id, &"health", ["current"]
	)

	print("[content-executor] Target health after: ", after)
	print("[content-executor] Actor health after: ", actor_health)

	return (
		before["ok"]
		and result["ok"]
		and after["ok"]
		and actor_health["ok"]
		and before["value"] == 100
		and after["value"] == 90
		and actor_health["value"] == 100
	)