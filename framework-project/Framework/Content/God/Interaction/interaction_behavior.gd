extends Node

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd"
)

@export var content: InteractionResource

var _bridge: WorldBridge
var _actor_node: Node


func configure_entity(bridge: WorldBridge, entity_node: Node) -> void:
	_bridge = bridge
	_actor_node = entity_node


func invoke(target_node: Node) -> Dictionary:
	if content == null:
		return _failure("Interaction behavior has no resource.")

	if String(content.id).strip_edges().is_empty():
		return _failure("Interaction behavior requires a resource ID.")

	if _bridge == null or not is_instance_valid(_actor_node):
		return _failure("Interaction behavior has no entity context.")

	if not is_instance_valid(target_node):
		return _failure("Interaction behavior target is invalid.")

	return _bridge.interact(
		content.id,
		_actor_node,
		target_node
	)


func _exit_tree() -> void:
	_bridge = null
	_actor_node = null


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}