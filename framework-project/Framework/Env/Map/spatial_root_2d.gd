extends RefCounted

const ROOT_META: StringName = &"entity_spatial_root"


static func find_for(entity_node: Node) -> Dictionary:
	if not is_instance_valid(entity_node):
		return _failure("Entity node is invalid.")

	var pending: Array[Node] = [entity_node]
	var found: Node2D = null

	while not pending.is_empty():
		var current: Node = pending.pop_back()

		if current != entity_node and (
			current.has_meta(&"entity_key")
			or current.has_meta(&"entity_definition")
		):
			continue

		var enabled: Variant = current.get_meta(ROOT_META, false)
		if typeof(enabled) != TYPE_BOOL:
			return _failure(
				"entity_spatial_root on '%s' must be a bool." % current.name
			)

		if enabled:
			var candidate := current as Node2D
			if candidate == null:
				return _failure("Entity spatial root must be Node2D.")

			if found != null:
				return _failure("Multiple entity spatial roots found.")

			found = candidate

		pending.append_array(current.get_children())

	return {"ok": true, "value": found, "error": ""}

static func capture_position(
	entity_node: Node,
	map_root: Node2D
) -> Dictionary:
	var resolved := _resolve_for_map(entity_node, map_root)
	if not resolved["ok"]:
		return resolved

	var spatial_root := resolved["value"] as Node2D
	if spatial_root == null:
		return resolved

	var position := map_root.to_local(spatial_root.global_position)
	if not position.is_finite():
		return _failure("Captured position must be finite.")

	return {"ok": true, "value": position, "error": ""}


static func restore_position(
	entity_node: Node,
	map_root: Node2D,
	map_position: Vector2
) -> Dictionary:
	if not map_position.is_finite():
		return _failure("Saved position must be finite.")

	var resolved := _resolve_for_map(entity_node, map_root)
	if not resolved["ok"]:
		return resolved

	var spatial_root := resolved["value"] as Node2D
	if spatial_root == null:
		return _failure("Entity has no enabled 2D spatial root.")

	var global_position := map_root.to_global(map_position)
	if not global_position.is_finite():
		return _failure("Restored global position must be finite.")

	var local_position: Vector2 = global_position
	var parent_item: CanvasItem = null

	if not spatial_root.is_set_as_top_level():
		parent_item = spatial_root.get_parent() as CanvasItem

	if parent_item != null:
		var parent_transform: Transform2D = parent_item.get_global_transform()
		var determinant: float = parent_transform.determinant()
		if not is_finite(determinant) or determinant == 0.0:
			return _failure("Spatial root parent transform cannot be inverted.")

		local_position = parent_transform.affine_inverse() * global_position

	if not local_position.is_finite():
		return _failure("Restored local position must be finite.")

	spatial_root.position = local_position

	return {"ok": true, "value": map_position, "error": ""}


static func _resolve_for_map(
	entity_node: Node,
	map_root: Node2D
) -> Dictionary:
	var discovered := find_for(entity_node)
	if not discovered["ok"]:
		return discovered

	var spatial_root := discovered["value"] as Node2D
	if spatial_root == null:
		return discovered

	if not is_instance_valid(map_root):
		return _failure("Map root is invalid.")

	if not spatial_root.is_inside_tree() or not map_root.is_inside_tree():
		return _failure("Position access requires nodes inside the scene tree.")

	if spatial_root != map_root and not map_root.is_ancestor_of(spatial_root):
		return _failure("Entity spatial root does not belong to this map.")

	if spatial_root.get_canvas() != map_root.get_canvas():
		return _failure("Entity spatial root and map use different canvases.")

	var determinant := map_root.global_transform.determinant()
	if not is_finite(determinant) or determinant == 0.0:
		return _failure("Map transform cannot be inverted.")

	return discovered


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}