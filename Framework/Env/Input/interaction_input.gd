extends Node

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)

@export var target_path: NodePath

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
		if not event.is_action_pressed(input_action, false):
			continue

		var interaction_id := StringName(_controls[input_action]["interaction"])
		var target_node := get_node_or_null(target_path)
		get_viewport().set_input_as_handled()

		var result := _bridge.interact(
			interaction_id, _actor_node, target_node
		)

		print("[input] %s: %s" % [interaction_id, result])
		return


func _exit_tree() -> void:
	_bridge = null
	_actor_node = null
	_controls = {}