extends RefCounted

const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")


static func build(value: Variant, path: Array, label: String, addressable: bool, state: Dictionary, editable_depth: int = 1) -> Dictionary:
	state["count"] += 1
	if path.size() > 64 or state["count"] > 10000:
		state["error"] = "Attribute trees cannot exceed 64 levels or 10000 entries."
		return {}
	var kind := type_string(typeof(value))
	var children: Array[Dictionary] = []
	if value is Dictionary:
		for key in value:
			var part := Values.segment(key)
			var child_path := path.duplicate()
			child_path.append(part)
			children.append(build(value[key], child_path, Values.value_text(key), addressable and part["kind"] != "unsupported", state, editable_depth))
			if not String(state["error"]).is_empty():
				break
	elif value is Array:
		for index in range(value.size()):
			var child_path := path.duplicate()
			child_path.append(Values.segment(index, true))
			children.append(build(value[index], child_path, "[%s]" % index, addressable, state, editable_depth))
			if not String(state["error"]).is_empty():
				break
	var scalar: bool = kind in Values.SCALARS and (not value is float or is_finite(value))
	return {
		"label": label, "kind": kind, "path": path,
		"value_text": Values.value_text(value), "children": children,
		"editable": addressable and path.size() >= editable_depth and scalar,
		"mutable": addressable and not path.is_empty(),
		"can_add": addressable and (value is Dictionary or value is Array),
	}
