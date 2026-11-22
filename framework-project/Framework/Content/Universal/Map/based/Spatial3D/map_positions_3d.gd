extends RefCounted

const Roles = preload("res://Framework/Content/Universal/Map/based/Spatial3D/spatial_roles_3d.gd")
const RECORD_KEY := "positions_3d"


static func snapshot(
	map: Node3D, entity_ids: Dictionary[StringName, int],
	bound_entity_ids: Array[int], node_for: Callable
) -> Dictionary:
	var positions: Dictionary[StringName, Vector3] = {}
	var keys := entity_ids.keys()
	keys.sort()
	for key: StringName in keys:
		var id: int = entity_ids[key]
		if not bound_entity_ids.has(id):
			continue
		var entity: Node = node_for.call(id)
		if entity == null:
			continue
		var found := Roles.find(entity, &"entity_spatial_root")
		if not found["ok"]:
			return found
		var body: Node3D = found["value"]
		if body == null:
			continue
		var error := _transform_error(map, body)
		if not error.is_empty():
			return Roles.failure(error)
		var position := map.to_local(body.global_position)
		if not position.is_finite():
			return Roles.failure("Captured 3D position for '%s' must be finite." % key)
		positions[key] = position
	return Roles.success({RECORD_KEY: positions})


static func prepare_restores(map: Node3D, placements: Array[Dictionary], saved: Dictionary) -> Dictionary:
	var remaining: Dictionary[StringName, Vector3] = {}
	for key in saved:
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or String(key).is_empty():
			return Roles.failure("Saved 3D position keys must be nonempty text.")
		var id := StringName(key)
		var position: Variant = saved[key]
		if remaining.has(id) or not position is Vector3 or not position.is_finite():
			return Roles.failure("Saved 3D position for '%s' must be unique and a finite Vector3." % id)
		remaining[id] = position

	var pending: Array[Dictionary] = []
	for placement in placements:
		var key: StringName = placement["key"]
		if not remaining.has(key):
			continue
		var found := Roles.find(placement["node"], &"entity_spatial_root")
		if not found["ok"] or found["value"] == null:
			return Roles.failure("Cannot restore '%s' without a valid 3D spatial root." % key)
		var body: Node3D = found["value"]
		if body != map and not map.is_ancestor_of(body):
			return Roles.failure("Entity '%s' does not belong to the 3D map." % key)
		pending.append({"body": body, "position": remaining[key]})
		remaining.erase(key)
	if not remaining.is_empty():
		return Roles.failure("Saved 3D position has no placement in this map: %s" % remaining.keys()[0])
	return Roles.success(pending)


static func restore(map: Node3D, pending: Array[Dictionary]) -> Dictionary:
	for entry in pending:
		var body: Node3D = entry["body"]
		var error := _transform_error(map, body)
		if not error.is_empty():
			return Roles.failure(error)
		var position := map.to_global(entry["position"])
		if not position.is_finite():
			return Roles.failure("Restored 3D position must be finite.")
		var parent := body.get_parent_node_3d()
		if parent != null and not body.top_level:
			var determinant := parent.global_transform.basis.determinant()
			if not is_finite(determinant) or determinant == 0.0:
				return Roles.failure("Spatial root parent transform cannot be inverted.")
		body.global_position = position
	return Roles.success(true)


static func _transform_error(map: Node3D, body: Node3D) -> String:
	if not map.is_inside_tree() or not body.is_inside_tree() or (body != map and not map.is_ancestor_of(body)):
		return "3D position access requires an entity in its active map."
	if body.get_world_3d() != map.get_world_3d():
		return "The spatial root and map use different 3D worlds."
	var determinant := map.global_transform.basis.determinant()
	if not is_finite(determinant) or determinant == 0.0:
		return "The 3D map transform cannot be inverted."
	return ""
