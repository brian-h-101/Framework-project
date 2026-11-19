extends RefCounted

const TARGET_META: StringName = &"interaction_target"


static func find_for(entity_node: Node) -> Dictionary:
	if not is_instance_valid(entity_node):
		return _failure("Entity node is invalid.")

	var pending: Array[Node] = [entity_node]
	var found: Node2D = null

	while not pending.is_empty():
		var current: Node = pending.pop_back()

		if current != entity_node and current.has_meta(&"entity_key"):
			continue

		var enabled: Variant = current.get_meta(TARGET_META, false)

		if typeof(enabled) != TYPE_BOOL:
			return _failure(
				"interaction_target on '%s' must be a bool." % current.name
			)

		if enabled:
			var candidate := current as Node2D

			if candidate == null:
				return _failure("Interaction target point must be Node2D.")

			if found != null:
				return _failure("Multiple interaction target points found.")

			found = candidate

		pending.append_array(current.get_children())

	if found == null:
		return _failure("Missing interaction target point.")

	return {"ok": true, "value": found, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}