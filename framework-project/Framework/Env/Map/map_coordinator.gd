extends RefCounted

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)
const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const MapPositions = preload(
	"res://Framework/Env/Map/map_positions.gd"
)
var _map_parent: Node
var _active_map: Node
var _bridge: WorldBridge
var _entity_ids: Dictionary[StringName, int] = {}
var _bound_entity_ids: Array[int] = []
var _controls: Dictionary[StringName, Dictionary] = {}
var _runtime: GameRuntime

func _init(
	map_parent: Node,
	bridge: WorldBridge,
	entity_ids: Dictionary[StringName, int],
	controls: Dictionary[StringName, Dictionary],
	runtime: GameRuntime
) -> void:
	_map_parent = map_parent
	_bridge = bridge
	_entity_ids = entity_ids
	_controls = controls
	_runtime = runtime


func load_map(
	scene: PackedScene,
	saved_positions: Dictionary = {}
) -> Dictionary:
	if not is_instance_valid(_map_parent):
		return _failure("Map parent is invalid.")

	if scene == null or not scene.can_instantiate():
		return _failure("Map scene cannot be instantiated.")

	var next_map := scene.instantiate()
	if next_map == null:
		return _failure("Map scene instantiation failed.")

	var prepared := _prepare_map_entities(next_map)
	if not prepared["ok"]:
		next_map.free()
		return prepared

	var placements: Array[Dictionary] = prepared["value"]

	var prepared_positions := MapPositions.prepare_restores(
		next_map,
		placements,
		saved_positions
	)
	if not prepared_positions["ok"]:
		next_map.free()
		return prepared_positions

	var position_restores: Array[Dictionary] = prepared_positions["value"]

	unload_map()

	_active_map = next_map
	_configure_runtime_components(_active_map)

	var bound := _bind_map_entities(placements)
	if not bound["ok"]:
		unload_map()
		return bound

	_map_parent.add_child(_active_map)

	var restored := MapPositions.restore(_active_map, position_restores)
	if not restored["ok"]:
		unload_map()
		return restored

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

func snapshot_map() -> Dictionary:
	var map_root := get_active_map()
	if map_root == null:
		return {"ok": true, "value": null, "error": ""}

	var scene_path := map_root.scene_file_path
	if scene_path.is_empty():
		return _failure("Active map has no scene file path.")

	var map_record: Dictionary = {
		"scene_path": scene_path,
	}

	var captured := MapPositions.snapshot(map_root, _entity_ids, _bound_entity_ids, _bridge.node_for)
	if not captured["ok"]:
		return captured
	map_record.merge(captured["value"])

	return {"ok": true, "value": map_record, "error": ""}

func _prepare_map_entities(map_root: Node) -> Dictionary:
	var nodes: Array[Node] = [map_root]
	nodes.append_array(map_root.find_children("*", "", true, false))

	var seen: Dictionary[StringName, bool] = {}
	var placements: Array[Dictionary] = []

	for world_node in nodes:
		if not world_node.has_meta(&"entity_key"):
			if world_node.has_meta(&"entity_definition"):
				return _failure(
					"Placed entity requires entity_key: %s" % world_node.name
				)
			continue

		var key_value: Variant = world_node.get_meta(&"entity_key")
		if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _failure("entity_key must be text on: %s" % world_node.name)

		var entity_key := StringName(key_value)
		if entity_key == &"":
			return _failure("Entity key cannot be empty.")

		if seen.has(entity_key):
			return _failure("Duplicate map entity key: %s" % entity_key)
		seen[entity_key] = true

		var definition_value: Variant = world_node.get_meta(&"entity_definition", &"")
		if typeof(definition_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _failure("entity_definition must be text on: %s" % world_node.name)

		var definition_id := StringName(definition_value)
		if definition_id != &"" and not _runtime.has_definition(definition_id):
			return _failure("Unknown entity definition: %s" % definition_id)

		if _entity_ids.has(entity_key):
			var entity_id: int = _entity_ids[entity_key]
			if not _runtime.has_entity(entity_id):
				return _failure("Missing runtime entity for key: %s" % entity_key)

			if (
				definition_id != &""
				and _runtime.definition_id_for(entity_id) != definition_id
			):
				return _failure(
					"Entity key '%s' already belongs to a different definition."
					% entity_key
				)

			if (
				_bridge.node_for(entity_id) != null
				and not _bound_entity_ids.has(entity_id)
			):
				return _failure(
					"Entity %s is already bound outside the active map." % entity_id
				)
		elif definition_id == &"":
			return _failure("Unknown map entity key: %s" % entity_key)

		placements.append({
			"node": world_node,
			"key": entity_key,
			"definition": definition_id,
		})

	return {"ok": true, "value": placements, "error": ""}


func _bind_map_entities(placements: Array[Dictionary]) -> Dictionary:
	for placement in placements:
		var world_node: Node = placement["node"]
		var entity_key: StringName = placement["key"]

		if not _entity_ids.has(entity_key):
			var definition_id: StringName = placement["definition"]
			var created_id := _runtime.spawn(definition_id)

			if created_id == 0:
				return _failure("Could not spawn map entity: %s" % entity_key)

			_entity_ids[entity_key] = created_id

		var entity_id: int = _entity_ids[entity_key]
		var bound := _bridge.bind_entity(entity_id, world_node)
		if not bound["ok"]:
			return bound

		_bound_entity_ids.append(entity_id)
		_configure_entity_components(world_node, world_node)

	return {"ok": true, "value": true, "error": ""}


func _configure_entity_components(
	entity_node: Node,
	component: Node
) -> void:
	if component != entity_node and component.has_meta(&"entity_key"):
		return

	if component.has_method(&"configure_entity"):
		component.call(&"configure_entity", _bridge, entity_node)

	if component.has_method(&"configure_controls"):
		component.call(&"configure_controls", _controls)

	for child in component.get_children():
		_configure_entity_components(entity_node, child)

func _configure_runtime_components(map_root: Node) -> void:
	var nodes: Array[Node] = [map_root]
	nodes.append_array(map_root.find_children("*", "", true, false))

	for component in nodes:
		if component.has_method(&"configure_runtime"):
			component.call(&"configure_runtime", _runtime)

		if component.has_method(&"configure_map"):
			component.call(&"configure_map", map_root)

func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
