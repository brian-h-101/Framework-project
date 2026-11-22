extends RefCounted


static func find(entity: Node, role: StringName) -> Dictionary:
	if not is_instance_valid(entity):
		return failure("The entity node is invalid.")
	var pending: Array[Node] = [entity]
	var found: Node3D
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current != entity and (current.has_meta(&"entity_key") or current.has_meta(&"entity_definition")):
			continue
		var enabled: Variant = current.get_meta(role, false)
		if typeof(enabled) != TYPE_BOOL:
			return failure("%s on '%s' must be a bool." % [role, current.name])
		if enabled:
			if not current is Node3D:
				return failure("%s requires a Node3D." % role)
			if found != null:
				return failure("Multiple nodes marked '%s'." % role)
			found = current as Node3D
		pending.append_array(current.get_children())
	return success(found)


static func success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


static func failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
