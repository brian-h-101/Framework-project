extends RefCounted

const Schema = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_schema.gd")
const Library = preload("res://Framework/Env/Authoring/Resources/Library/behavior_library.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Collections = preload("res://Framework/Env/Authoring/Shared/collection_editing.gd")
const Executors = preload("res://Framework/Env/Authoring/Resources/Inspection/executor_catalog.gd")


static func edit(source: String, request: Dictionary) -> Dictionary:
	var checked := Files.check_path(source)
	if not checked["ok"]:
		return checked
	checked = Executors.unchanged(request.get("executor_snapshot"))
	if not checked["ok"]:
		return checked
	var hashes: Variant = request.get("expected_hashes")
	var catalog: Variant = request.get("catalog_paths")
	var seed: Variant = request.get("catalog_seed")
	if not hashes is Dictionary or not hashes.has(source) or not catalog is Array or not seed is String:
		return Values.failure("Edits require the inspected Resource hashes and catalogue snapshot.")
	checked = Files.check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	checked = Library.unchanged(seed, catalog)
	if not checked["ok"]:
		return checked
	var loaded := Library.load_library(seed)
	if not loaded["ok"]:
		return loaded
	var library: Dictionary = loaded["value"]
	checked = Files.check_hashes(hashes, library["hashes"])
	if not checked["ok"]:
		return checked
	var resource := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource == null or Schema.kind(resource).is_empty():
		return Values.failure("Choose a supported behavior Resource.")
	var changed := _apply(resource, request)
	if not changed["ok"]:
		return changed
	var error := Schema.validate(resource)
	if not error.is_empty():
		return Values.failure(error)
	if resource is Schema.Action:
		for consumer: Resource in library["resources"].values():
			if consumer is Schema.Interaction and consumer.action != null and consumer.action.resource_path == source:
				error = Schema.argument_error(consumer, resource)
				if not error.is_empty():
					return Values.failure(error)
	checked = Library.unchanged(seed, catalog)
	if not checked["ok"]:
		return checked
	return Files.save(source, hashes, resource, Schema.snapshot, _guard.bind(seed, catalog, request["executor_snapshot"]), true)


static func _guard(staged: String, seed: String, catalog: Array, snapshot: Dictionary) -> Dictionary:
	var checked := Library.unchanged(seed, catalog)
	return Executors.unchanged(snapshot, staged) if checked["ok"] else checked


static func _apply(resource: Resource, request: Dictionary) -> Dictionary:
	if resource is Schema.Behavior:
		return Schema.Sequence.apply(resource, request)
	var operation: Variant = request.get("operation")
	if operation == "set_reference":
		return _set_reference(resource, request)
	if operation == "set_interaction":
		var path: Variant = request.get("interaction_path")
		if not resource is Schema.Automation or not path is String:
			return Values.failure("Choose an Automation and a saved Interaction Resource.")
		var checked := Files.check_path(path)
		if not checked["ok"]:
			return checked
		if not request["expected_hashes"].has(path):
			return Values.failure("Inspect the selected Interaction before assignment.")
		var interaction := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if not interaction is Schema.Interaction:
			return Values.failure("Expected an Interaction Resource: " + path)
		resource.interaction = interaction
		return Values.success(true)
	if operation == "set_behavior":
		if not resource is Schema.Action or not request.get("behavior_id") is String:
			return Values.failure("Choose an action and a registered executor behavior.")
		var description := Executors.describe(StringName(request["behavior_id"]))
		if not description["ok"]:
			return description
		resource.behavior_id = StringName(request["behavior_id"])
		return Values.success(true)
	if operation == "remove_condition":
		var selected_index: Variant = request.get("condition_index")
		if not resource is Schema.Group or typeof(selected_index) not in [TYPE_INT, TYPE_FLOAT]:
			return Values.failure("Choose a condition linked beneath a condition group.")
		if not is_finite(float(selected_index)) or float(selected_index) != floor(float(selected_index)) or selected_index < 0 or selected_index >= resource.conditions.size():
			return Values.failure("The selected condition index is invalid. Refresh and retry.")
		var index := int(selected_index)
		if index < 0 or index >= resource.conditions.size() or resource.conditions[index] == null or resource.conditions[index].resource_path != request.get("condition_path"):
			return Values.failure("The selected condition relationship changed. Refresh and retry.")
		resource.conditions.remove_at(index)
		return Values.success(true)
	if operation == "clear_requirements":
		if not resource is Schema.Interaction or resource.requirements == null:
			return Values.failure("Choose an interaction with an assigned requirement group.")
		resource.requirements = null
		return Values.success(true)
	if operation == "add_effect":
		if not resource is Schema.Action or not request.get("effect") is Dictionary:
			return Values.failure("Add a complete effect to an action Resource.")
		var description := Executors.describe(resource.behavior_id)
		if not description["ok"]:
			return description
		if not description["value"]["supports_effects"]:
			return Values.failure("The selected behavior does not support attribute effects.")
		var effect: Dictionary = request["effect"].duplicate(true)
		var error := Schema.effect_error(effect)
		if not error.is_empty():
			return Values.failure(error)
		for key in ["entity", "operation", "container", "value_from"]:
			effect[key] = StringName(effect[key])
		resource.effects.append(effect)
		return Values.success(true)
	if operation not in ["add", "set", "rename", "remove"]:
		return Values.failure("Unsupported behavior editing operation.")
	var path: Variant = request.get("path")
	if not path is Array or path.is_empty():
		return Values.failure("Choose a nested behavior data entry.")
	for part in path:
		if not part is Dictionary or not part.get("kind") is String or not part.get("text") is String or part["kind"] not in ["String", "StringName", "int", "index"]:
			return Values.failure("Behavior paths require typed key or index segments.")
	if operation in ["rename", "remove"] and Schema.protected_key(resource, path, operation):
		return Values.failure("Required behavior schema fields cannot be renamed or removed.")
	if resource is Schema.Automation:
		if operation != "set" or path.size() != 1 or String(path[0]["text"]) not in ["trigger", "targeting", "interval_seconds", "cooldown_seconds"]:
			return Values.failure("Choose an existing Automation setting to edit.")
		var allowed := ["int", "float"] if String(path[0]["text"]).ends_with("_seconds") else ["StringName", "String"]
		if request.get("value_type") not in allowed:
			return Values.failure("The Automation setting has an incompatible value type.")
	if operation == "add" and resource is Schema.Action and path.size() == 1:
		return Values.failure("Use Add Effect to append a complete validated effect.")
	var fields := Schema.fields(resource)
	var changed := Collections.apply(fields, request)
	if not changed["ok"]:
		return changed
	for key in fields:
		resource.set(key, fields[key])
	return Values.success(true)


static func _set_reference(resource: Resource, request: Dictionary) -> Dictionary:
	var role: Variant = request.get("role")
	var target: Variant = request.get("target_path")
	if not target is String or not request["expected_hashes"].has(target):
		return Values.failure("Inspect the selected Resource before assignment.")
	var checked := Files.check_path(target)
	if not checked["ok"]:
		return checked
	var selected := ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource is Schema.Interaction and role == "action" and selected is Schema.Action:
		resource.action = selected
	elif resource is Schema.Interaction and role == "requirements" and selected is Schema.Group:
		resource.requirements = selected
	elif resource is Schema.Automation and role == "interaction" and selected is Schema.Interaction:
		resource.interaction = selected
	elif resource is Schema.Group and role == "condition" and selected is Schema.Condition:
		var index: Variant = request.get("condition_index", -1)
		if typeof(index) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(index)) or float(index) != floor(float(index)) or index < -1 or index >= resource.conditions.size():
			return Values.failure("The selected condition index is invalid. Refresh and retry.")
		for position in resource.conditions.size():
			if position != int(index) and resource.conditions[position].id == selected.id:
				return Values.failure("Condition '%s' is already assigned to this group." % selected.id)
		if int(index) == -1:
			resource.conditions.append(selected)
		else:
			if resource.conditions[int(index)].resource_path != request.get("condition_path"):
				return Values.failure("The selected condition relationship changed. Refresh and retry.")
			resource.conditions[int(index)] = selected
	else:
		return Values.failure("This Resource type is incompatible with the selected relationship.")
	return Values.success(true)
