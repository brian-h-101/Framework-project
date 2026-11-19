extends Node

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)
const TargetResolver2D = preload(
	"res://Framework/Env/Targeting/target_resolver_2d.gd"
)

var _bridge: WorldBridge
var _actor_node: Node
var _controls: Dictionary[StringName, Dictionary] = {}


func configure_entity(bridge: WorldBridge, entity_node: Node) -> void:
	_bridge = bridge
	_actor_node = entity_node


func configure_controls(controls: Dictionary[StringName, Dictionary]) -> void:
	_controls = controls


func _ready() -> void:
	if _bridge == null or not is_instance_valid(_actor_node):
		push_error("Interaction input has no entity context.")
		set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if _bridge == null:
		return

	for input_action in _controls:
		var control: Dictionary = _controls[input_action]
		if not control.has("interaction"):
			continue

		if not event.is_action_pressed(input_action, false):
			continue

		get_viewport().set_input_as_handled()

		var result := _execute_control(control)

		print("[input] %s: %s" % [control["interaction"], result])
		return


func _execute_control(control: Dictionary) -> Dictionary:
	if not control.has("targeting"):
		return {
			"ok": false,
			"value": null,
			"error": "Missing targeting rule for interaction: %s" %
				control["interaction"],
		}

	var mode := StringName(control["targeting"])
	var selected := TargetResolver2D.resolve(
		_bridge, _actor_node, mode
	)

	if not selected["ok"]:
		return selected

	var interaction_id := StringName(control["interaction"])
	var target_node := selected["value"] as Node

	return _bridge.interact(
		interaction_id, _actor_node, target_node
	)


func _exit_tree() -> void:
	_bridge = null
	_actor_node = null
	_controls = {}