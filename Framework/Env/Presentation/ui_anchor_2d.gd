extends RefCounted

const ROLE_META: StringName = &"ui_anchor_role"


static func find_for(
	entity_node: Node,
	role: StringName = &"status"
) -> Dictionary:
	if not is_instance_valid(entity_node):
		return _failure("Entity node is invalid.")

	if role == &"":
		return _failure("UI anchor role is empty.")

	var pending: Array[Node] = [entity_node]
	var found: Node2D = null

	while not pending.is_empty():
		var current: Node = pending.pop_back()

		if current != entity_node and current.has_meta(&"entity_key"):
			continue

		if current.has_meta(ROLE_META):
			var declared_role: Variant = current.get_meta(ROLE_META)

			if typeof(declared_role) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return _failure(
					"UI anchor role on '%s' must be text." % current.name
				)

			if StringName(declared_role) == role:
				var candidate := current as Node2D

				if candidate == null:
					return _failure(
						"UI anchor for role '%s' must be Node2D." % role
					)

				if found != null:
					return _failure(
						"Multiple UI anchors for role: %s." % role
					)

				found = candidate

		pending.append_array(current.get_children())

	if found == null:
		return _failure("Missing UI anchor for role: %s." % role)

	return {"ok": true, "value": found, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}