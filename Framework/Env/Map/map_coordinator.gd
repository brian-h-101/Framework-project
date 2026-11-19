extends RefCounted

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)
const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const SpatialRoot2D = preload(
	"res://Framework/Env/Map/spatial_root_2d.gd"
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

	var prepared_positions := _prepare_position_restores(
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

	for restoration in position_restores:
		var entity_node: Node = restoration["node"]
		var map_position: Vector2 = restoration["position"]

		var restored := SpatialRoot2D.restore_position(
			entity_node,
			_active_map as Node2D,
			map_position
		)
		if not restored["ok"]:
			var message: String = (
				"Cannot restore position for '%s': %s"
				% [restoration["key"], restored["error"]]
			)
			unload_map()
			return _failure(message)

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

	if map_root is Node2D:
		var captured := _snapshot_positions_2d(map_root as Node2D)
		if not captured["ok"]:
			return captured

		map_record["positions_2d"] = captured["value"]

	return {"ok": true, "value": map_record, "error": ""}

func _snapshot_positions_2d(map_root: Node2D) -> Dictionary:
	var positions: Dictionary[StringName, Vector2] = {}
	var entity_keys := _entity_ids.keys()
	entity_keys.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)

	for entity_key: StringName in entity_keys:
		var entity_id: int = _entity_ids[entity_key]
		if not _bound_entity_ids.has(entity_id):
			continue

		var entity_node := _bridge.node_for(entity_id)
		if entity_node == null:
			continue

		var captured := SpatialRoot2D.capture_position(
			entity_node,
			map_root
		)
		if not captured["ok"]:
			return _failure(
				"Cannot capture position for '%s': %s"
				% [entity_key, captured["error"]]
			)

		if captured["value"] != null:
			positions[entity_key] = captured["value"]

	return {"ok": true, "value": positions, "error": ""}

func _prepare_position_restores(
	map_root: Node,
	placements: Array[Dictionary],
	saved_positions: Dictionary
) -> Dictionary:
	if not saved_positions.is_empty() and not (map_root is Node2D):
		return _failure("Saved 2D positions require a Node2D map.")

	var pending_positions: Dictionary[StringName, Vector2] = {}

	for saved_key in saved_positions:
		if typeof(saved_key) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _failure("Saved position keys must be text.")

		var entity_key := StringName(saved_key)
		if entity_key == &"":
			return _failure("Saved position key cannot be empty.")

		if pending_positions.has(entity_key):
			return _failure("Duplicate saved position key: %s" % entity_key)

		var position_value: Variant = saved_positions[saved_key]
		if typeof(position_value) != TYPE_VECTOR2:
			return _failure(
				"Saved position for '%s' must be Vector2." % entity_key
			)

		var position: Vector2 = position_value
		if not position.is_finite():
			return _failure(
				"Saved position for '%s' must be finite." % entity_key
			)

		pending_positions[entity_key] = position

	var restores: Array[Dictionary] = []

	for placement in placements:
		var entity_key: StringName = placement["key"]
		if not pending_positions.has(entity_key):
			continue

		var entity_node: Node = placement["node"]
		var discovered := SpatialRoot2D.find_for(entity_node)
		if not discovered["ok"]:
			return _failure(
				"Cannot restore position for '%s': %s"
				% [entity_key, discovered["error"]]
			)

		if discovered["value"] == null:
			return _failure(
				"Entity '%s' has no enabled 2D spatial root." % entity_key
			)

		restores.append({
			"node": entity_node,
			"key": entity_key,
			"position": pending_positions[entity_key],
		})
		pending_positions.erase(entity_key)

	if not pending_positions.is_empty():
		return _failure(
			"Saved position has no placement in this map: %s"
			% pending_positions.keys()[0]
		)

	return {"ok": true, "value": restores, "error": ""}

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
	parent_node: Node
) -> void:
	for component in parent_node.get_children():
		if component.has_meta(&"entity_key"):
			continue

		if component.has_method(&"configure_entity"):
			component.call(&"configure_entity", _bridge, entity_node)

		if component.has_method(&"configure_controls"):
			component.call(&"configure_controls", _controls)

		_configure_entity_components(entity_node, component)

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
