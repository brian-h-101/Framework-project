extends RefCounted

const Behavior = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")
const Condition = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd")
const Requirements = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Definition = preload("res://Framework/Infrastructure/Implementation/Gameplay/Behavior/behavior_definition.gd")
const ValueTree = preload("res://Framework/Env/Authoring/Shared/value_tree.gd")
const Collections = preload("res://Framework/Env/Authoring/Shared/collection_editing.gd")

const Executors = preload("res://Framework/Env/Authoring/Resources/Inspection/executor_catalog.gd")

static func snapshot(resource: Resource) -> Dictionary:
	# Compare embedded content, never staging-file ::SubResource paths.
	return {"definition": resource.read(), "ownership": _ownership(resource),
		"name": resource.resource_name, "local": resource.resource_local_to_scene}

static func _ownership(resource: Resource) -> Array:
	var output := []
	for step in _flatten(resource.steps):
		var references := []
		if step.requirements != null:
			for condition in step.requirements.conditions:
				references.append(_external_path(condition))
		output.append([String(step.id), _external_path(step), _external_path(step.requirements), references])
	return output

static func _external_path(resource: Resource) -> String:
	return "" if resource == null or resource.resource_path.contains("::") else resource.resource_path

static func validate(resource: Resource) -> String:
	var checked: Dictionary = resource.read()
	return checked["error"] if not checked["ok"] else Definition.validation_error(checked["value"], Executors.describe)

static func tree(resource: Resource) -> Dictionary:
	var checked: Dictionary = resource.read()
	if not checked["ok"]:
		return checked
	var root := _row("Behavior", "root")
	var configuration := _row("Configuration", "configuration")
	for field: String in resource.configuration.to_definition():
		var value: Variant = resource.configuration.get(field)
		var row := _row(field.replace("_", " ").capitalize(), "configuration", "", {"field": field, "value_type": type_string(typeof(value)), "value_text": Values.value_text(value)})
		row["value_text"] = Values.value_text(value)
		configuration["children"].append(row)
	root["children"] = [configuration, _steps_row(resource.steps, "")]
	return Values.success(root)

static func _steps_row(steps: Array, parent: String) -> Dictionary:
	var row := _row("Steps [SEQUENCE]", "steps", parent)
	for step in steps:
		var item := _row((step.label if not step.label.is_empty() else String(step.id)) + (" [GROUP]" if step is Behavior.GroupStep else " [ACTION]"), "step", String(step.id), {"parent_id": parent, "label": step.label, "step_kind": "group" if step is Behavior.GroupStep else "action"})
		var requirements := _row("Requirements [ALL]", "requirements", String(step.id))
		if step.requirements != null:
			for index in step.requirements.conditions.size():
				var condition: Resource = step.requirements.conditions[index]
				var value: Dictionary = condition.requirement
				var label := "%s: %s.%s %s %s" % [condition.id, value.get("entity", ""), value.get("container", ""), value.get("operator", ""), Values.value_text(value.get("value"))]
				requirements["children"].append(_row(label, "condition", String(step.id), {"condition_index": index, "condition_path": _external_path(condition), "condition_id": String(condition.id), "requirement": value}))
		item["children"].append(requirements)
		if step is Behavior.GroupStep:
			item["children"].append(_steps_row(step.steps, String(step.id)))
		else:
			var executor := _row("Executor: " + String(step.executor_id), "executor", String(step.id), {"executor_id": String(step.executor_id)})
			var state := {"count": 0, "error": ""}
			var data := ValueTree.build({"arguments": step.arguments, "effects": step.effects}, [], "data", true, state, 2)
			if not String(state["error"]).is_empty():
				executor["value_text"] = "Argument tree is read-only: " + String(state["error"])
			else:
				for entry: Dictionary in data["children"]:
					_decorate(entry, step)
					executor["children"].append(entry)
			item["children"].append(executor)
		row["children"].append(item)
	return row

static func _row(label: String, role: String, step_id: String = "", extra: Dictionary = {}) -> Dictionary:
	var metadata := {"role": role, "step_id": step_id}
	metadata.merge(extra)
	return {"label": label, "kind": "Behavior", "path": [], "value_text": "", "children": [],
		"editable": false, "mutable": false, "can_add": false, "can_rename": false,
		"can_remove": false, "can_add_effect": false, "allowed_types": [], "choices": [], "sequence": metadata}

static func apply(resource: Resource, request: Dictionary) -> Dictionary:
	if not resource is Behavior:
		return Values.failure("Choose a unified Behavior Resource.")
	var readable: Dictionary = resource.read()
	if not readable["ok"]:
		return readable
	var id: Variant = request.get("step_id", "")
	if not id is String:
		return Values.failure("Step ID must be text.")
	var step: Resource = null
	var siblings: Array = resource.steps
	for candidate in _flatten(resource.steps):
		if String(candidate.id) == id:
			step = candidate
	if not id.is_empty() and step == null:
		return Values.failure("Step no longer exists. Refresh and retry.")
	if not request.get("operation") is String:
		return Values.failure("Sequence operation must be text.")
	var operation: String = request["operation"]
	if operation in ["set", "add", "rename", "remove", "add_effect"]:
		if not step is Behavior.ActionStep:
			return Values.failure("Choose an Action step argument or effect.")
		if operation == "add_effect":
			if not request.get("effect") is Dictionary:
				return Values.failure("An effect requires a complete definition.")
			step.effects.append(request["effect"])
			return Values.success(true)
		var path: Variant = request.get("path")
		if not path is Array or path.is_empty() or not path[0] is Dictionary or path[0].get("text") not in ["arguments", "effects"] or (operation != "add" and path.size() <= 1):
			return Values.failure("Choose a nested executor argument or effect entry.")
		var data := {"arguments": step.arguments.duplicate(true), "effects": step.effects.duplicate(true)}
		var changed := Collections.apply(data, request)
		if changed["ok"]:
			step.arguments = data["arguments"]
			step.effects.assign(data["effects"])
		return changed
	if operation == "sequence_configure":
		var field: Variant = request.get("field")
		if field not in ["trigger", "event_id", "targeting", "interval_seconds", "cooldown_seconds"]:
			return Values.failure("Choose a Configuration field.")
		var parsed := _value(request)
		if not parsed["ok"]:
			return parsed
		var value: Variant = parsed["value"]
		if field in ["trigger", "targeting"] and not value is String or field == "event_id" and typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return Values.failure("Configuration field requires text.")
		if field.ends_with("_seconds") and not Definition.number(value):
			return Values.failure("Configuration timing requires a finite number.")
		resource.configuration = resource.configuration.duplicate(true)
		resource.configuration.set(field, value)
	elif operation == "sequence_add":
		if step != null and not step is Behavior.GroupStep:
			return Values.failure("Only Groups can contain child steps.")
		var kind: Variant = request.get("step_kind")
		if kind not in ["action", "group"] or not request.get("new_id") is String or String(request["new_id"]).strip_edges().is_empty() or not request.get("label", "") is String:
			return Values.failure("New steps require a kind, unique ID and text label.")
		var created: Resource = Behavior.ActionStep.new() if kind == "action" else Behavior.GroupStep.new()
		created.id = StringName(request["new_id"])
		created.label = request.get("label", "")
		if kind == "action":
			var result := _executor(created, request)
			if not result["ok"]:
				return result
		if step != null:
			step.steps.append(created)
		else:
			resource.steps.append(created)
	elif operation in ["sequence_remove", "sequence_move", "sequence_rename"]:
		if step == null:
			return Values.failure("Choose a step.")
		if operation == "sequence_rename":
			if not request.get("label") is String or String(request["label"]).strip_edges().is_empty():
				return Values.failure("Step display label cannot be empty.")
			step.label = request["label"]
		else:
			siblings = _siblings(resource.steps, step)
			var index := siblings.find(step)
			if operation == "sequence_remove":
				siblings.remove_at(index)
			else:
				var direction: Variant = request.get("direction")
				if direction not in [-1, 1] or index + int(direction) < 0 or index + int(direction) >= siblings.size():
					return Values.failure("Step cannot move beyond its siblings.")
				siblings.remove_at(index)
				siblings.insert(index + int(direction), step)
	elif operation == "sequence_executor":
		if not step is Behavior.ActionStep:
			return Values.failure("Choose an Action step.")
		return _executor(step, request)
	elif operation in ["sequence_condition", "sequence_remove_condition"]:
		if step == null:
			return Values.failure("Choose a step's Requirements.")
		var group := Requirements.new()
		group.id = StringName(String(step.id) + "_requirements")
		if step.requirements != null:
			group.conditions.assign(step.requirements.conditions)
		var index: Variant = request.get("condition_index", -1)
		if typeof(index) not in [TYPE_INT, TYPE_FLOAT] or float(index) != floor(float(index)) or index < -1 or index >= group.conditions.size():
			return Values.failure("Condition index is stale or invalid.")
		if operation == "sequence_remove_condition":
			if index < 0:
				return Values.failure("Choose a condition.")
			group.conditions.remove_at(int(index))
		else:
			var condition: Resource
			if request.has("condition_path"):
				var path: Variant = request["condition_path"]
				if not path is String or not request["expected_hashes"].has(path):
					return Values.failure("Inspect the selected Condition before assignment.")
				condition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
				if not condition is Condition:
					return Values.failure("Expected a Condition Resource.")
			else:
				if not request.get("requirement") is Dictionary or not request.get("condition_id") is String:
					return Values.failure("Inline conditions require an ID and requirement.")
				condition = Condition.new()
				condition.id = StringName(request["condition_id"])
				condition.requirement = request["requirement"].duplicate(true)
				var parsed := _value(condition.requirement)
				if not parsed["ok"]:
					return parsed
				condition.requirement.erase("value_type")
				condition.requirement.erase("value_text")
				condition.requirement["value"] = parsed["value"]
			if index < 0:
				group.conditions.append(condition)
			else:
				group.conditions[int(index)] = condition
		step.requirements = group # Copy on write: shared Group files are preserved.
	else:
		return Values.failure("Unsupported sequence operation.")
	return Values.success(true)

static func _executor(step: Resource, request: Dictionary) -> Dictionary:
	if not request.get("executor_id") is String or not request.get("arguments", []) is Array or not request.get("effects", []) is Array:
		return Values.failure("Choose an executor and typed arguments.")
	var arguments := {}
	for item in request.get("arguments", []):
		if not item is Dictionary or not item.get("name") is String or String(item["name"]).is_empty() or arguments.has(StringName(item["name"])):
			return Values.failure("Argument names must be unique nonempty text.")
		var parsed := _value(item)
		if not parsed["ok"]:
			return parsed
		arguments[StringName(item["name"])] = parsed["value"]
	step.executor_id = StringName(request["executor_id"])
	step.arguments = step.arguments.duplicate(true)
	step.arguments.merge(arguments, true)
	if request.has("effects"):
		step.effects.assign(request["effects"])
	return Values.success(true)

static func _value(request: Dictionary) -> Dictionary:
	return Values.parse(request["value_type"], request["value_text"]) if request.get("value_type") is String and request.get("value_text") is String else Values.failure("Choose a typed value.")

static func _flatten(steps: Array) -> Array:
	var output := []
	for step in steps:
		output.append(step)
		if step is Behavior.GroupStep:
			output.append_array(_flatten(step.steps))
	return output

static func _siblings(steps: Array, selected: Resource) -> Array:
	if steps.has(selected):
		return steps
	for step in steps:
		if step is Behavior.GroupStep:
			var found := _siblings(step.steps, selected)
			if not found.is_empty():
				return found
	return []

static func _decorate(node: Dictionary, step: Resource) -> void:
	node["sequence"] = {"role": "argument_data", "step_id": String(step.id)}
	var path: Array = node["path"]
	node["can_rename"] = path.size() > 1 and path[-1]["kind"] != "index"
	node["can_remove"] = path.size() > 1
	node["can_add_effect"] = path.size() == 1 and path[0]["text"] == "effects" and step.executor_id == &"attribute_effects"
	node["allowed_types"] = []
	node["choices"] = []
	if path.size() == 1 and path[0]["text"] == "effects":
		node["can_add"] = false
	for child: Dictionary in node["children"]:
		_decorate(child, step)
