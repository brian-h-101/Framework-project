extends SceneTree

const Runtime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const Core = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)
const Executor = preload(
	"res://Framework/Content/Executor/change_health_executor.gd"
)
const Action = preload(
	"res://Framework/Content/Behavior/Action/change_health.tres"
)


func _initialize() -> void:
	var runtime := Runtime.new(Core.new())
	var passed := _run_check(runtime)

	runtime.close()

	var closed := runtime.execute_action(
		Action.id, 0, 0, {&"amount": -10}
	)
	var closed_ok: bool = (
		not closed["ok"]
		and closed["error"] == "Game runtime is closed."
	)

	print("[direct-action] Closed runtime rejected: ", closed_ok)
	print("[direct-action] Checks passed: ", passed and closed_ok)

	quit(0 if passed and closed_ok else 1)


func _run_check(runtime: Runtime) -> bool:
	var registered := runtime.register_executor(
		Executor.BEHAVIOR_ID,
		Executor.new()
	)
	print("[direct-action] Executor registered: ", registered["ok"])

	if not registered["ok"]:
		return false

	var defined := runtime.define_action(Action.to_definition())
	print("[direct-action] Action registered: ", defined["ok"])

	if not defined["ok"]:
		return false

	var containers: Dictionary[StringName, Dictionary] = {
		&"health": {"current": 100},
	}
	runtime.define_attributes(&"direct_action_probe", containers)

	var actor_id: int = runtime.spawn(&"direct_action_probe")
	var target_id: int = runtime.spawn(&"direct_action_probe")

	var result := runtime.execute_action(
		Action.id,
		actor_id,
		target_id,
		{&"amount": -10}
	)
	var target_health := runtime.read_attribute(
		target_id, &"health", ["current"]
	)
	var actor_health := runtime.read_attribute(
		actor_id, &"health", ["current"]
	)

	print("[direct-action] Result: ", result)
	print("[direct-action] Target health: ", target_health)
	print("[direct-action] Actor health: ", actor_health)

	if not (
		result["ok"]
		and result["value"] == 90
		and target_health["ok"]
		and target_health["value"] == 90
		and actor_health["ok"]
		and actor_health["value"] == 100
	):
		return false

	var rejections: Array[Dictionary] = [
		runtime.execute_action(
			&"missing_action", actor_id, target_id, {&"amount": -10}
		),
		runtime.execute_action(
			&"", actor_id, target_id, {&"amount": -10}
		),
		runtime.execute_action(
			Action.id, -1, target_id, {&"amount": -10}
		),
		runtime.execute_action(
			Action.id, actor_id, -1, {&"amount": -10}
		),
		runtime.execute_action(
			Action.id, actor_id, target_id, {}
		),
		runtime.execute_action(
			Action.id, actor_id, target_id, {&"amount": "invalid"}
		),
	]

	var rejected := true
	for rejection: Dictionary in rejections:
		rejected = (
			rejected
			and not rejection["ok"]
			and rejection["value"] == null
			and not String(rejection["error"]).is_empty()
		)

	var unchanged := runtime.read_attribute(
		target_id, &"health", ["current"]
	)
	var preserved: bool = (
		unchanged["ok"] and unchanged["value"] == 90
	)

	print("[direct-action] Invalid calls rejected: ", rejected)
	print("[direct-action] Rejected calls preserve health: ", preserved)

	return rejected and preserved