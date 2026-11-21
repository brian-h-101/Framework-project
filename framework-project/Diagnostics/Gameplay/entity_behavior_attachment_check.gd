extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)
const Behavior = preload(
	"res://Framework/Content/God/Interaction/interaction_behavior.gd"
)
const InteractionInput = preload(
	"res://Framework/Content/God/Interaction/interaction_input.gd"
)
const Controls = preload(
	"res://Framework/Content/Configuration/Input/controls.tres"
)
var _host := GameHost.new()


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var passed := _check_attachment()

	_host.stop()
	await process_frame

	print("[behavior-attachment] Checks passed: ", passed)
	quit(0 if passed else 1)


func _check_attachment() -> bool:
	var started := _host.start(root)
	print("[behavior-attachment] Host started: ", started)

	if not started["ok"]:
		return false

	var map_root: Node = _host.maps.get_active_map()
	if map_root == null:
		return false

	var player := map_root.get_node_or_null("Player")
	var enemy := map_root.get_node_or_null("Enemy")
	var entities_found: bool = player != null and enemy != null

	print("[behavior-attachment] Entity nodes found: ", entities_found)

	if not entities_found:
		return false

	var behavior := player.get_node_or_null("StrikeBehavior") as Behavior
	print("[behavior-attachment] Component found: ", behavior != null)

	if behavior == null or behavior.content == null:
		return false

	if behavior.content.action == null:
		return false

	print(
		"[behavior-attachment] Executor behavior: ",
		behavior.content.action.behavior_id
	)

	print(
		"[behavior-attachment] Attached resource: ",
		behavior.content.resource_path
	)
	var input_node := player.get_node_or_null(
		"InteractionInput"
	) as InteractionInput

	if input_node == null:
		return false

	var controls := Controls.read()
	if not controls["ok"]:
		return false

	var control: Dictionary = controls["value"][&"primary_interaction"]
	var bridge := _host.entry.world_bridge
	var before := bridge.read_attribute(enemy, &"health", ["current"])
	var result := input_node._execute_control(control)
	var after := bridge.read_attribute(enemy, &"health", ["current"])

	print("[behavior-attachment] Enemy health before: ", before)
	print("[behavior-attachment] Invocation: ", result)
	print("[behavior-attachment] Enemy health after: ", after)

	return (
		behavior.content.id == &"strike"
		and behavior.content.resource_path == "res://Framework/Content/Behavior/Interaction/strike.tres"
		and behavior.content.action.behavior_id == &"change_health"
		and behavior.content.action.effects.is_empty()
		and before["ok"]
		and result["ok"]
		and after["ok"]
		and after["value"] == before["value"] - 10
		and result["value"] == after["value"]
	)
