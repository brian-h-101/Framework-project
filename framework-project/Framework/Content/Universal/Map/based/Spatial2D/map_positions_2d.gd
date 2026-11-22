extends RefCounted

const SpatialRoot2D = preload("res://Framework/Content/Universal/Map/based/Spatial2D/spatial_root_2d.gd")
const RECORD_KEY := "positions_2d"


static func read_saved_positions(map_record: Dictionary) -> Dictionary:
	var positions: Variant = map_record.get(RECORD_KEY, {})
	if not positions is Dictionary:
		return _failure("Saved map positions_2d must be a dictionary.")
	return {"ok": true, "value": positions, "error": ""}


static func snapshot(
	map_root: Node,
	entity_ids: Dictionary[StringName, int],
	bound_entity_ids: Array[int],
	node_for: Callable
) -> Dictionary:
	var map_2d := map_root as Node2D
	if map_2d == null:
		return {"ok": true, "value": {}, "error": ""}

	var positions: Dictionary[StringName, Vector2] = {}
	var entity_keys := entity_ids.keys()
	entity_keys.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)

	for entity_key: StringName in entity_keys:
		var entity_id: int = entity_ids[entity_key]
		if not bound_entity_ids.has(entity_id):
			continue

		var entity_node: Node = node_for.call(entity_id)
		if entity_node == null:
			continue

		var captured := SpatialRoot2D.capture_position(entity_node, map_2d)
		if not captured["ok"]:
			return _failure("Cannot capture position for '%s': %s" % [entity_key, captured["error"]])

		if captured["value"] != null:
			positions[entity_key] = captured["value"]

	return {"ok": true, "value": {RECORD_KEY: positions}, "error": ""}


static func prepare_restores(
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
			return _failure("Saved position for '%s' must be Vector2." % entity_key)

		var position: Vector2 = position_value
		if not position.is_finite():
			return _failure("Saved position for '%s' must be finite." % entity_key)

		pending_positions[entity_key] = position

	var restores: Array[Dictionary] = []

	for placement in placements:
		var entity_key: StringName = placement["key"]
		if not pending_positions.has(entity_key):
			continue

		var entity_node: Node = placement["node"]
		var discovered := SpatialRoot2D.find_for(entity_node)
		if not discovered["ok"]:
			return _failure("Cannot restore position for '%s': %s" % [entity_key, discovered["error"]])

		if discovered["value"] == null:
			return _failure("Entity '%s' has no enabled 2D spatial root." % entity_key)

		restores.append({
			"node": entity_node,
			"key": entity_key,
			"position": pending_positions[entity_key],
		})
		pending_positions.erase(entity_key)

	if not pending_positions.is_empty():
		return _failure("Saved position has no placement in this map: %s" % pending_positions.keys()[0])

	return {"ok": true, "value": restores, "error": ""}


static func restore(map_root: Node, restorations: Array[Dictionary]) -> Dictionary:
	var map_2d := map_root as Node2D
	for restoration in restorations:
		var restored := SpatialRoot2D.restore_position(restoration["node"], map_2d, restoration["position"])
		if not restored["ok"]:
			return _failure("Cannot restore position for '%s': %s" % [restoration["key"], restored["error"]])

	return {"ok": true, "value": true, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
