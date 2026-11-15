extends Node

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)

@export var input_action: StringName = &"primary_interaction"
@export var interaction_id: StringName = &"strike"
@export var target_path: NodePath

var _bridge: WorldBridge
var _actor_node: Node


func configure_entity(bridge: WorldBridge, entity_node: Node) -> void:
	_bridge = bridge
	_actor_node = entity_node


func _ready() -> void:
	if _bridge == null or not is_instance_valid(_actor_node):
		push_error("Interaction input has no entity context.")
		set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if _bridge == null or not event.is_action_pressed(input_action, false):
		return

	var target_node := get_node_or_null(target_path)
	get_viewport().set_input_as_handled()

	var result := _bridge.interact(
		interaction_id, _actor_node, target_node
	)

	print("[input] %s: %s" % [interaction_id, result])


func _exit_tree() -> void:
	_bridge = null
	_actor_node = null