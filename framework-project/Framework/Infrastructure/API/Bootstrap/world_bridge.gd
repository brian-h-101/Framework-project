extends RefCounted

signal entity_bound(entity_id: int, world_node: Node)
signal entity_unbound(entity_id: int)

signal attribute_written(
	world_node: Node,
	container_id: StringName,
	attribute_name: StringName
)

const RuntimeCore = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)
const WorldBridgeCore = preload(
	"res://Framework/Infrastructure/Implementation/Bootstrap/world_bridge_core.gd"
)

var _core: WorldBridgeCore


func _init(runtime_core: RuntimeCore) -> void:
	_core = WorldBridgeCore.new(runtime_core)
	_core.attribute_written.connect(_on_core_attribute_written)
	_core.entity_bound.connect(_on_core_entity_bound)
	_core.entity_unbound.connect(_on_core_entity_unbound)

func close() -> void:
	_core.close()

	if _core.entity_bound.is_connected(_on_core_entity_bound):
		_core.entity_bound.disconnect(_on_core_entity_bound)

	if _core.entity_unbound.is_connected(_on_core_entity_unbound):
		_core.entity_unbound.disconnect(_on_core_entity_unbound)

	if _core.attribute_written.is_connected(_on_core_attribute_written):
		_core.attribute_written.disconnect(_on_core_attribute_written)

func bind_entity(entity_id: int, world_node: Node) -> Dictionary:
	return _core.bind_entity(entity_id, world_node)


func bind_automation(world_node: Node, id: StringName, enabled: bool = true) -> Dictionary:
	return _core.bind_automation(world_node, id, enabled)


func node_for(entity_id: int) -> Node:
	return _core.node_for(entity_id)


func entity_for(world_node: Node) -> int:
	return _core.entity_for(world_node)


func unbind_entity(entity_id: int) -> bool:
	return _core.unbind_entity(entity_id)


func read_attribute(
	world_node: Node,
	container_id: StringName,
	path: Array
) -> Dictionary:
	return _core.read_attribute(world_node, container_id, path)


func interact(
	interaction_id: StringName,
	actor_node: Node,
	target_node: Node
) -> Dictionary:
	return _core.interact(interaction_id, actor_node, target_node)

func execute_action(
	action_id: StringName,
	actor_node: Node,
	target_node: Node,
	arguments: Dictionary = {}
) -> Dictionary:
	return _core.execute_action(
		action_id,
		actor_node,
		target_node,
		arguments
	)

func _on_core_attribute_written(
	world_node: Node,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	attribute_written.emit(world_node, container_id, attribute_name)

func bound_entity_ids() -> Array[int]:
	return _core.bound_entity_ids()

func _on_core_entity_bound(entity_id: int, world_node: Node) -> void:
	entity_bound.emit(entity_id, world_node)


func _on_core_entity_unbound(entity_id: int) -> void:
	entity_unbound.emit(entity_id)
