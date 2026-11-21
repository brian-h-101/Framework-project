extends RefCounted

const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")


static func apply(containers: Dictionary, request: Dictionary) -> Dictionary:
	var path: Variant = request.get("path")
	if not path is Array or path.size() > 64:
		return Values.failure("An edit requires a typed attribute path.")
	var operation: Variant = request.get("operation")
	if operation == "add":
		var target := Values.locate(containers, path)
		if not target["ok"]:
			return target
		var parent: Variant = target["value"]
		var parsed := _value(request)
		if not parsed["ok"]:
			return parsed
		var value: Variant = parsed["value"]
		if parent is Array:
			if not Values.accepts(parent, null, value):
				return Values.failure("The value does not match the typed array.")
			parent.append(value)
		elif parent is Dictionary:
			if not request.get("key") is Dictionary:
				return Values.failure("Adding a dictionary entry requires a typed key.")
			var parsed_key := Values.key_for(parent, request["key"], false)
			if not parsed_key["ok"]:
				return parsed_key
			var key: Variant = parsed_key["value"]
			if parent.has(key):
				return Values.failure("The dictionary already contains that key.")
			if not Values.accepts(parent, key, value):
				return Values.failure("The key or value does not match the typed dictionary.")
			parent[key] = value
		else:
			return Values.failure("Add entries to a dictionary or array.")
		return Values.success(true)
	if operation not in ["set", "rename", "remove"] or path.is_empty():
		return Values.failure("Choose an attribute entry and a supported operation.")
	var located := Values.locate(containers, path.slice(0, -1))
	if not located["ok"]:
		return located
	var parent: Variant = located["value"]
	if not path[-1] is Dictionary:
		return Values.failure("Paths require typed key segments.")
	var found := Values.key_for(parent, path[-1])
	if not found["ok"]:
		return found
	var key: Variant = found["value"]
	match operation:
		"set":
			if type_string(typeof(parent[key])) not in Values.SCALARS:
				return Values.failure("This native value is read-only. Edit collection entries individually.")
			var parsed := _value(request)
			if not parsed["ok"]:
				return parsed
			if not Values.accepts(parent, key, parsed["value"]):
				return Values.failure("The value does not match the typed collection.")
			parent[key] = parsed["value"]
		"remove":
			if parent is Array:
				parent.remove_at(key)
			else:
				parent.erase(key)
		"rename":
			if not parent is Dictionary or not request.get("key") is Dictionary:
				return Values.failure("Rename requires a dictionary entry and a typed key.")
			var parsed := Values.key_for(parent, request["key"], false)
			if not parsed["ok"]:
				return parsed
			var new_key: Variant = parsed["value"]
			if parent.has(new_key):
				return Values.failure("The dictionary already contains that key.")
			if not Values.accepts(parent, new_key, parent[key]):
				return Values.failure("The new key does not match the typed dictionary.")
			parent[new_key] = parent[key]
			parent.erase(key)
	return Values.success(true)


static func _value(request: Dictionary) -> Dictionary:
	if not request.get("value_type") is String or not request.get("value_text") is String:
		return Values.failure("Values require a native type and textual value.")
	return Values.parse(request["value_type"], request["value_text"])


