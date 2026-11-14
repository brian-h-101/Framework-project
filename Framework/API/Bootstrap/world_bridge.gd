extends RefCounted

signal attribute_written(
	world_node: Node,
	container_id: StringName,
	attribute_name: StringName
)

const RuntimeCore = preload(
	"res://Framework/Implementation/Runtime/runtime_core.gd"
)
const WorldBridgeCore = preload(
	"res://Framework/Implementation/Bootstrap/world_bridge_core.gd"
)

var _core: WorldBridgeCore


func _init(runtime_core: RuntimeCore) -> void:
	_core = WorldBridgeCore.new(runtime_core)
	_core.attribute_written.connect(_on_core_attribute_written)

func close() -> void:
	if _core.attribute_written.is_connected(_on_core_attribute_written):
		_core.attribute_written.disconnect(_on_core_attribute_written)

	_core.close()

func bind_entity(entity_id: int, world_node: Node) -> Dictionary:
	return _core.bind_entity(entity_id, world_node)


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


func _on_core_attribute_written(
	world_node: Node,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	attribute_written.emit(world_node, container_id, attribute_name)
