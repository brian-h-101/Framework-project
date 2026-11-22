extends RefCounted

const Policy = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")
const Schema = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_schema.gd")
const Shared = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Executors = preload("res://Framework/Env/Authoring/Resources/Inspection/executor_catalog.gd")


static func catalogue() -> Dictionary:
	var executors := Executors.refresh()
	if not executors["ok"]:
		return executors
	var folders := Policy.folders()
	if not folders["ok"]:
		return folders
	var entries: Array[Dictionary] = [_directory(Policy.ROOT, "", "root")]
	for folder: String in folders["value"]:
		var category := folder.get_base_dir()
		var library := Shared.catalogue(folder, Policy.path_error, _describe)
		if not library["ok"]:
			return library
		var contents: Array = library["value"]["entries"]
		entries.append(_directory(category, Policy.ROOT, "folder"))
		contents[0]["kind"] = "folder"
		contents[0]["parent_path"] = category
		entries.append_array(contents)
		if entries.size() > 10001:
			return Values.failure("The Behavior library exceeds 10000 entries.")
	var result := {"version": 1, "root_path": Policy.ROOT, "entries": entries}
	result.merge(executors["value"])
	return Values.success(result)


static func _directory(path: String, parent: String, kind: String) -> Dictionary:
	return {
		"source_path": path, "parent_path": parent, "name": path.get_file(),
		"kind": kind, "fingerprint": Shared.fingerprint(path), "supported": false,
	}


static func _describe(resource: Resource) -> Dictionary:
	var kind := Schema.kind(resource)
	var arguments: Array = []
	var valid := not kind.is_empty() and Schema.validate(resource).is_empty()
	if resource is Schema.Action and valid:
		arguments = Executors.arguments_for(resource)["value"]
	return {"supported": not kind.is_empty(), "resource_kind": kind,
		"id": String(resource.id) if not kind.is_empty() else "", "valid": valid, "argument_specs": arguments}


static func entries_snapshot(value: Dictionary) -> Dictionary:
	var result := {}
	for entry in value["entries"]:
		result[entry["source_path"]] = entry["fingerprint"]
	return result


static func _guard(request: Dictionary) -> Dictionary:
	if not request.get("expected_entries") is Dictionary:
		return Values.failure("Resource creation requires the inspected Behavior library snapshot.")
	var current := catalogue()
	if not current["ok"]:
		return current
	var checked := Executors.unchanged(request.get("executor_snapshot"))
	if not checked["ok"]:
		return checked
	return current if entries_snapshot(current["value"]) == request["expected_entries"] else Values.failure("The Behavior library changed. Refresh and retry.")


static func draft(path: String, request: Dictionary) -> Dictionary:
	var error := Policy.resource_error(path)
	if error.is_empty():
		error = Policy.name_error(path.get_file())
	if error.is_empty():
		error = Shared.target_error(path, request.get("expected_parent"))
	if not error.is_empty():
		return Values.failure(error)
	var current := _guard(request)
	if not current["ok"]:
		return current
	var kind: Variant = request.get("resource_kind")
	var id: Variant = request.get("id")
	if kind not in ["action", "condition", "condition_group", "interaction", "automation", "behavior"] or not id is String or String(id).strip_edges().is_empty() or String(id).to_utf8_buffer().has(0):
		return Values.failure("Choose a supported behavior type and a nonempty authored ID.")
	for entry in current["value"]["entries"]:
		if entry.get("resource_kind") == kind and entry.get("id") == id:
			return Values.failure("Duplicate %s ID '%s' in %s." % [kind, id, entry["source_path"]])
	var made := _create(kind, id, request)
	if not made["ok"]:
		return made
	var resource: Resource = made["value"]
	error = Schema.validate(resource)
	if not error.is_empty():
		return Values.failure(error)
	var drafted := Shared.draft(path, request.get("expected_parent"), resource, Schema.snapshot)
	if not drafted["ok"]:
		return drafted
	current = _guard(request)
	return drafted if current["ok"] else current


static func _create(kind: String, id: String, request: Dictionary) -> Dictionary:
	var resource: Resource
	match kind:
		"behavior":
			resource = Schema.Behavior.new()
			resource.configuration = Schema.Behavior.Configuration.new()
		"automation":
			var interaction := _reference(request.get("interaction_path"), Schema.Interaction)
			if not interaction["ok"]:
				return interaction
			resource = Schema.Automation.new()
			resource.interaction = interaction["value"]
			for field in ["interval_seconds", "cooldown_seconds"]:
				var value: Variant = request.get(field, 1.0)
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
					return Values.failure("Automation timing must use finite numbers.")
				resource.set(field, float(value))
		"action":
			resource = Schema.Action.new()
			var behavior: Variant = request.get("behavior_id", "attribute_effects")
			if not behavior is String:
				return Values.failure("Choose a registered executor behavior.")
			resource.behavior_id = StringName(behavior)
		"condition_group":
			resource = Schema.Group.new()
		"condition":
			var definition: Variant = request.get("requirement")
			if not definition is Dictionary or not definition.get("value_type") is String or not definition.get("value_text") is String:
				return Values.failure("Conditions require a complete address and typed numeric comparison.")
			var number := Values.parse(definition["value_type"], definition["value_text"])
			if not number["ok"]:
				return number
			resource = Schema.Condition.new()
			resource.requirement = definition.duplicate(true)
			resource.requirement.erase("value_type")
			resource.requirement.erase("value_text")
			resource.requirement["value"] = number["value"]
		"interaction":
			var action := _reference(request.get("action_path"), Schema.Action)
			if not action["ok"]:
				return action
			resource = Schema.Interaction.new()
			resource.action = action["value"]
			var group_path: Variant = request.get("requirements_path", "")
			if group_path != "":
				var group := _reference(group_path, Schema.Group)
				if not group["ok"]:
					return group
				resource.requirements = group["value"]
			var arguments: Variant = request.get("arguments", [])
			if not arguments is Array:
				return Values.failure("Interaction arguments require typed named values.")
			for argument in arguments:
				if not argument is Dictionary or not argument.get("name") is String or String(argument["name"]).is_empty() or not argument.get("value_type") is String or not argument.get("value_text") is String:
					return Values.failure("Interaction arguments require typed named values.")
				var key := StringName(argument["name"])
				if resource.arguments.has(key):
					return Values.failure("Duplicate interaction argument: " + String(key))
				var parsed := Values.parse(argument["value_type"], argument["value_text"])
				if not parsed["ok"]:
					return parsed
				resource.arguments[key] = parsed["value"]
	resource.id = StringName(id)
	return Values.success(resource)


static func _reference(path: Variant, schema: Script) -> Dictionary:
	if not path is String:
		return Values.failure("Select a saved behavior Resource reference.")
	var error := Policy.resource_error(path)
	if not error.is_empty():
		return Values.failure(error)
	var checked := Files.check_path(path)
	if not checked["ok"]:
		return checked
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	return Values.success(resource) if is_instance_of(resource, schema) else Values.failure("The selected reference has the wrong behavior type: " + path)


static func deletion_preview(path: String, request: Dictionary) -> Dictionary:
	var error := Policy.resource_error(path)
	if not error.is_empty():
		return Values.failure(error)
	var checked := Files.check_path(path)
	if not checked["ok"]:
		return checked
	var target := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var kind := Schema.kind(target)
	if kind.is_empty():
		return Values.failure("Choose a supported behavior Resource for deletion.")
	var result := Shared.deletion_preview(path, request.get("expected_hash"))
	if not result["ok"]:
		return result
	var snapshot: Dictionary = result["value"]
	if kind in ["action", "interaction", "automation", "behavior"] and not String(target.id).is_empty():
		for source: String in snapshot["hashes"]:
			if source == path:
				continue
			var found := false
			if source.get_extension() in ["tres", "res"]:
				var resource := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
				if resource != null:
					for property in resource.get_property_list():
						if int(property["usage"]) & PROPERTY_USAGE_STORAGE and String(property["name"]) not in ["id", "script"]:
							found = found or _id_reference(resource.get(property["name"]), kind, String(target.id), String(property["name"]), 0)
			elif source.get_extension() in ["gd", "godot"]:
				found = Shared.has_literal(FileAccess.get_file_as_string(source), String(target.id))
			elif source.get_extension() in ["tscn", "scn"]:
				var scene := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
				if scene != null:
					var state := scene.get_state()
					for node in state.get_node_count():
						for property in state.get_node_property_count(node):
							var name := String(state.get_node_property_name(node, property))
							found = found or _id_reference({name: state.get_node_property_value(node, property)}, kind, String(target.id), "", 0)
			if found and not snapshot["consumers"].any(func(consumer: Dictionary) -> bool: return consumer["source_path"] == source):
				snapshot["consumers"].append({"source_path": source, "kind": "authored_id"})
	checked = Shared.verify_snapshot(snapshot)
	return result if checked["ok"] else checked


static func _id_reference(value: Variant, kind: String, id: String, parent: String, depth: int) -> bool:
	if depth > 64:
		return false
	if value is Dictionary:
		for key in value:
			var name := str(key)
			var field: Variant = value[key]
			var fields := ["behavior", "behavior_id"] if kind == "behavior" else ["automation", "automation_id"] if kind == "automation" else ["interaction", "interaction_id"] if kind == "interaction" else ["action", "action_id"]
			var direct := name in fields
			if direct and typeof(field) in [TYPE_STRING, TYPE_STRING_NAME] and String(field) == id:
				return true
			if kind == "interaction" and parent == "interactions" and name == "available" and field is Array and field.has(StringName(id)):
				return true
			if _id_reference(field, kind, id, name, depth + 1):
				return true
	elif value is Array:
		for entry in value:
			if _id_reference(entry, kind, id, parent, depth + 1):
				return true
	return false
