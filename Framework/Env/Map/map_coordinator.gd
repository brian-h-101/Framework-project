extends RefCounted

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)

var _map_parent: Node
var _active_map: Node
var _bridge: WorldBridge
var _entity_ids: Dictionary[StringName, int] = {}
var _bound_entity_ids: Array[int] = []


func _init(
	map_parent: Node,
	bridge: WorldBridge,
	entity_ids: Dictionary[StringName, int]
) -> void:
	_map_parent = map_parent
	_bridge = bridge
	_entity_ids = entity_ids


func load_map(scene: PackedScene) -> Dictionary:
	if not is_instance_valid(_map_parent):
		return _failure("Map parent is invalid.")

	if scene == null or not scene.can_instantiate():
		return _failure("Map scene cannot be instantiated.")

	var next_map := scene.instantiate()
	if next_map == null:
		return _failure("Map scene instantiation failed.")

	unload_map()

	_active_map = next_map

	var bound := _bind_map_entities(_active_map)
	if not bound.ok:
		unload_map()
		return bound

	_map_parent.add_child(_active_map)

	return {"ok": true, "value": _active_map, "error": ""}


func unload_map() -> void:
	for entity_id in _bound_entity_ids:
		_bridge.unbind_entity(entity_id)

	_bound_entity_ids.clear()

	if not is_instance_valid(_active_map):
		_active_map = null
		return

	var previous_map := _active_map
	_active_map = null

	var parent := previous_map.get_parent()
	if parent != null:
		parent.remove_child(previous_map)

	previous_map.queue_free()


func get_active_map() -> Node:
	if not is_instance_valid(_active_map):
		_active_map = null

	return _active_map


func _bind_map_entities(map_root: Node) -> Dictionary:
	var nodes: Array[Node] = [map_root]
	nodes.append_array(map_root.find_children("*", "", true, false))

	for world_node in nodes:
		if not world_node.has_meta(&"entity_key"):
			continue

		var entity_key := StringName(world_node.get_meta(&"entity_key"))
		if not _entity_ids.has(entity_key):
			return _failure("Unknown map entity key: %s" % entity_key)

		var entity_id: int = _entity_ids[entity_key]
		var bound := _bridge.bind_entity(entity_id, world_node)
		if not bound.ok:
			return bound

		_bound_entity_ids.append(entity_id)

		for component in world_node.get_children():
			if component.has_method(&"configure_entity"):
				component.call(&"configure_entity", _bridge, world_node)

	return {"ok": true, "value": true, "error": ""}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}