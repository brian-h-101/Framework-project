extends SceneTree

const Entry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const Setup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)
const Behavior = preload(
	"res://Framework/Content/Universal/Interaction/based/Legacy/interaction_behavior.gd"
)
const Interaction = preload(
	"res://Diagnostics/Fixtures/GameplayResources/strike.tres"
)


func _initialize() -> void:
	var entry := Entry.new()
	var actor_node := Node.new()
	var target_node := Node.new()
	var behavior := Behavior.new()

	behavior.content = Interaction
	actor_node.add_child(behavior)

	var passed := _run_check(
		entry, actor_node, target_node, behavior
	)

	entry.stop()
	actor_node.free()
	target_node.free()

	print("[interaction-behavior] Checks passed: ", passed)
	quit(0 if passed else 1)


func _run_check(
	entry: Entry,
	actor_node: Node,
	target_node: Node,
	behavior: Behavior
) -> bool:
	var started := entry.start(Setup.new())
	print("[interaction-behavior] Session started: ", started)

	if not started["ok"]:
		return false

	var runtime = entry.runtime

	var action_registered: Dictionary = runtime.define_action(
		Interaction.action.to_definition()
	)
	var interaction_registered: Dictionary = runtime.define_interaction(
		Interaction.to_definition()
	)

	print("[interaction-behavior] Action registered: ", action_registered)
	print("[interaction-behavior] Interaction registered: ", interaction_registered)

	if not action_registered["ok"] or not interaction_registered["ok"]:
		return false

	var containers: Dictionary[StringName, Dictionary] = {
		&"health": {"current": 100},
		&"strength": {"current": 10},
		&"interactions": {"available": [Interaction.id]},
	}

	runtime.define_attributes(&"interaction_behavior_probe", containers)

	var actor_id: int = runtime.spawn(&"interaction_behavior_probe")
	var target_id: int = runtime.spawn(&"interaction_behavior_probe")

	var actor_bound := entry.world_bridge.bind_entity(actor_id, actor_node)
	var target_bound := entry.world_bridge.bind_entity(target_id, target_node)

	print("[interaction-behavior] Actor bound: ", actor_bound)
	print("[interaction-behavior] Target bound: ", target_bound)

	if not actor_bound["ok"] or not target_bound["ok"]:
		return false

	behavior.configure_entity(entry.world_bridge, actor_node)

	var result := behavior.invoke(target_node)
	var target_health: Dictionary = runtime.read_attribute(
		target_id, &"health", ["current"]
	)
	var actor_health: Dictionary = runtime.read_attribute(
		actor_id, &"health", ["current"]
	)

	print("[interaction-behavior] Invocation: ", result)
	print("[interaction-behavior] Target health: ", target_health)
	print("[interaction-behavior] Actor health: ", actor_health)

	if not result["ok"] or not target_health["ok"] or not actor_health["ok"]:
		return false

	if target_health["value"] != 90 or actor_health["value"] != 100:
		return false

	var weakened: Dictionary = runtime.write_attribute(
		actor_id, &"strength", ["current"], 9
	)
	if not weakened["ok"]:
		return false

	var rejected := behavior.invoke(target_node)
	var after_rejection: Dictionary = runtime.read_attribute(
		target_id, &"health", ["current"]
	)

	print("[interaction-behavior] Invocation at strength 9: ", rejected)
	print("[interaction-behavior] Health after rejection: ", after_rejection)

	return (
		not rejected["ok"]
		and after_rejection["ok"]
		and after_rejection["value"] == 90
	)
