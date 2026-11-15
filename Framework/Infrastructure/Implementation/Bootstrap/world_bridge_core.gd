extends RefCounted

signal attribute_written(
	world_node: Node,
	container_id: StringName,
	attribute_name: StringName
)

const RuntimeCore = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)

var _runtime: RuntimeCore
var _nodes: Dictionary[int, WeakRef] = {}
var _closed: bool = false

func _init(runtime: RuntimeCore) -> void:
	_runtime = runtime
	_runtime.attribute_written.connect(_on_runtime_attribute_written)

func close() -> void:
	if _closed:
		return

	_closed = true

	if _runtime.attribute_written.is_connected(_on_runtime_attribute_written):
		_runtime.attribute_written.disconnect(_on_runtime_attribute_written)

	_nodes.clear()
	_runtime = null

func bind_entity(entity_id: int, world_node: Node) -> Dictionary:
	if _closed:
		return _failure("World bridge is closed.")
	if not _runtime.has_entity(entity_id):
		return _failure("Unknown runtime entity: %s" % entity_id)

	if not is_instance_valid(world_node):
		return _failure("World node is invalid.")

	if node_for(entity_id) != null:
		return _failure(
			"Entity %s already has a world node." % entity_id
		)

	if entity_for(world_node) != 0:
		return _failure("World node is already bound.")

	_nodes[entity_id] = weakref(world_node)

	return {"ok": true, "value": entity_id, "error": ""}


func node_for(entity_id: int) -> Node:
	var node_ref: WeakRef = _nodes.get(entity_id)
	if node_ref == null:
		return null

	var world_node := node_ref.get_ref() as Node
	if world_node == null:
		_nodes.erase(entity_id)

	return world_node


func entity_for(world_node: Node) -> int:
	if not is_instance_valid(world_node):
		return 0

	for entity_id in _nodes.keys():
		if node_for(entity_id) == world_node:
			return entity_id

	return 0


func unbind_entity(entity_id: int) -> bool:
	return _nodes.erase(entity_id)

func read_attribute(
	world_node: Node,
	container_id: StringName,
	path: Array
) -> Dictionary:
	if _closed:
		return _failure("World bridge is closed.")
	var entity_id := entity_for(world_node)
	if entity_id == 0:
		return _failure(
			"World node is not bound to a runtime entity."
		)

	return _runtime.read_attribute(entity_id, container_id, path)

func interact(
	interaction_id: StringName,
	actor_node: Node,
	target_node: Node
) -> Dictionary:
	if _closed:
		return _failure("World bridge is closed.")
	var actor_id := entity_for(actor_node)
	if actor_id == 0:
		return _failure(
			"Actor node is not bound to a runtime entity."
		)

	var target_id := entity_for(target_node)
	if target_id == 0:
		return _failure(
			"Target node is not bound to a runtime entity."
		)

	return _runtime.interact(interaction_id, actor_id, target_id)

func _on_runtime_attribute_written(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	var world_node := node_for(entity_id)
	if world_node == null:
		return

	attribute_written.emit(world_node, container_id, attribute_name)

func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
