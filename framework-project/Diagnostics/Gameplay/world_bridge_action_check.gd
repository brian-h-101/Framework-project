extends SceneTree

const Runtime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const Core = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)
const Bridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)
const Action = preload(
	"res://Diagnostics/Fixtures/GameplayResources/change_health.tres"
)


func _initialize() -> void:
	var core := Core.new()
	var runtime := Runtime.new(core)
	var bridge := Bridge.new(core)

	var actor_node := Node.new()
	var target_node := Node.new()
	var unbound_node := Node.new()

	var passed := _run_check(
		runtime, bridge, actor_node, target_node, unbound_node
	)

	bridge.close()

	var closed := bridge.execute_action(
		Action.id, actor_node, target_node, {&"amount": -10}
	)
	var closed_ok: bool = (
		not closed["ok"]
		and closed["error"] == "World bridge is closed."
	)

	runtime.close()
	actor_node.free()
	target_node.free()
	unbound_node.free()

	print("[bridge-action] Closed bridge rejected: ", closed_ok)
	print("[bridge-action] Checks passed: ", passed and closed_ok)

	quit(0 if passed and closed_ok else 1)


func _run_check(
	runtime: Runtime,
	bridge: Bridge,
	actor_node: Node,
	target_node: Node,
	unbound_node: Node
) -> bool:
	if not runtime.has_executor(Action.behavior_id):
		return false

	var defined := runtime.define_action(Action.to_definition())
	if not defined["ok"]:
		return false

	var containers: Dictionary[StringName, Dictionary] = {
		&"health": {"current": 100},
	}
	runtime.define_attributes(&"bridge_action_probe", containers)

	var actor_id: int = runtime.spawn(&"bridge_action_probe")
	var target_id: int = runtime.spawn(&"bridge_action_probe")

	var actor_bound := bridge.bind_entity(actor_id, actor_node)
	var target_bound := bridge.bind_entity(target_id, target_node)
	var bound: bool = actor_bound["ok"] and target_bound["ok"]

	print("[bridge-action] Nodes bound: ", bound)

	if not bound:
		return false

	var writes: Array = []
	bridge.attribute_written.connect(
		func(
			world_node: Node,
			container_id: StringName,
			attribute_name: StringName
		) -> void:
			writes.append([world_node, container_id, attribute_name])
	)

	var result := bridge.execute_action(
		Action.id, actor_node, target_node, {&"amount": -10}
	)
	var target_health := runtime.read_attribute(
		target_id, &"health", ["current"]
	)
	var notified: bool = (
		writes == [[target_node, &"health", &"current"]]
	)

	print("[bridge-action] Result: ", result)
	print("[bridge-action] Target health: ", target_health)
	print("[bridge-action] Node notification correct: ", notified)

	if not (
		result["ok"]
		and result["value"] == [90]
		and target_health["ok"]
		and target_health["value"] == 90
		and notified
	):
		return false

	writes.clear()

	var self_result := bridge.execute_action(
		Action.id, actor_node, actor_node, {&"amount": -5}
	)
	print("[bridge-action] Self-targeted action: ", self_result)

	if not (
		self_result["ok"]
		and self_result["value"] == [95]
		and writes == [[actor_node, &"health", &"current"]]
	):
		return false

	writes.clear()

	var rejections: Array[Dictionary] = [
		bridge.execute_action(
			Action.id, unbound_node, target_node, {&"amount": -10}
		),
		bridge.execute_action(
			Action.id, actor_node, unbound_node, {&"amount": -10}
		),
		bridge.execute_action(
			Action.id, null, target_node, {&"amount": -10}
		),
		bridge.execute_action(
			Action.id, actor_node, null, {&"amount": -10}
		),
		bridge.execute_action(
			&"missing_action", actor_node, target_node, {}
		),
		bridge.execute_action(
			Action.id, actor_node, target_node, {}
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

	print("[bridge-action] Invalid requests rejected: ", rejected)

	var removed := bridge.unbind_entity(target_id)
	var detached := bridge.execute_action(
		Action.id, actor_node, target_node, {&"amount": -10}
	)
	var detached_rejected: bool = removed and not detached["ok"]

	print("[bridge-action] Unbound node rejected: ", detached_rejected)

	var final_target := runtime.read_attribute(
		target_id, &"health", ["current"]
	)
	var final_actor := runtime.read_attribute(
		actor_id, &"health", ["current"]
	)
	var preserved: bool = (
		final_target["ok"]
		and final_target["value"] == 90
		and final_actor["ok"]
		and final_actor["value"] == 95
		and writes.is_empty()
	)

	print("[bridge-action] Runtime state preserved: ", preserved)

	return rejected and detached_rejected and preserved
