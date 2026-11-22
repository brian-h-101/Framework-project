extends RefCounted

const Behavior = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")
const Sequence = preload("res://Framework/Env/Authoring/Resources/Behavior/sequence_authoring.gd")

const Action = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Actions/action_resource.gd")
const Interaction = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd")
const Condition = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd")
const Group = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd")
const Automation = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Automation/automation_resource.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const ValueTree = preload("res://Framework/Env/Authoring/Shared/value_tree.gd")
const Executors = preload("res://Framework/Env/Authoring/Resources/Inspection/executor_catalog.gd")
const Contract = preload("res://Framework/Infrastructure/Implementation/Gameplay/Registry/executor_contract.gd")
const EFFECT_KEYS = ["operation", "entity", "container", "path", "value_from"]
const REQUIREMENT_KEYS = ["entity", "container", "path", "operator", "value"]


static func kind(resource: Resource) -> String:
	if resource is Behavior:
		return "behavior"
	if resource is Automation:
		return "automation"
	if resource is Action:
		return "action"
	if resource is Interaction:
		return "interaction"
	if resource is Condition:
		return "condition"
	if resource is Group:
		return "condition_group"
	return ""


static func fields(resource: Resource) -> Dictionary:
	if resource is Automation:
		return {"trigger": resource.trigger, "targeting": resource.targeting,
			"interval_seconds": resource.interval_seconds, "cooldown_seconds": resource.cooldown_seconds}
	if resource is Action:
		return {"behavior_id": resource.behavior_id, "effects": resource.effects.duplicate(true)}
	if resource is Interaction:
		return {"arguments": resource.arguments.duplicate(true)}
	if resource is Condition:
		return {"requirement": resource.requirement.duplicate(true)}
	return {}


static func snapshot(resource: Resource) -> Dictionary:
	if resource is Behavior:
		return Sequence.snapshot(resource)
	var data := fields(resource)
	data["id"] = resource.id
	if resource is Action:
		data["behavior_id"] = resource.behavior_id
	data["schema"] = resource.get_script().resource_path
	data["resource_name"] = resource.resource_name
	data["resource_local_to_scene"] = resource.resource_local_to_scene
	var metadata := {}
	for key in resource.get_meta_list():
		metadata[key] = resource.get_meta(key)
	data["metadata"] = metadata
	if resource is Interaction:
		data["action"] = resource.action
		data["requirements"] = resource.requirements
	elif resource is Group:
		data["conditions"] = resource.conditions
	elif resource is Automation:
		data["interaction"] = resource.interaction
	return data


static func validate(resource: Resource) -> String:
	if resource is Behavior:
		return Sequence.validate(resource)
	if resource is Automation:
		var error: String = resource.validation_error()
		return error if not error.is_empty() else validate(resource.interaction)
	if kind(resource).is_empty() or String(resource.id).is_empty():
		return "Behavior Resources require a supported schema and nonempty authored ID."
	if resource is Action:
		if String(resource.behavior_id).strip_edges().is_empty():
			return "Action Resources require a nonempty behavior ID."
		var prepared := Executors.arguments_for(resource)
		if not prepared["ok"]:
			return prepared["error"]
	elif resource is Condition:
		var error := address_error(resource.requirement)
		if not error.is_empty():
			return error
		if not _text(resource.requirement.get("operator")) or String(resource.requirement["operator"]) not in ["==", "!=", ">", ">=", "<", "<="]:
			return "Conditions require a supported comparison operator."
		if not _number(resource.requirement.get("value")) and not resource.requirement.get("value") is bool:
			return "Condition comparisons require a finite numeric or boolean value."
		if resource.requirement.get("value") is bool and resource.requirement["operator"] not in ["==", "!="]:
			return "Boolean comparisons support only == and !=."
		if resource.requirement.has("message") and not _text(resource.requirement["message"], true):
			return "Condition messages must be text."
	elif resource is Group:
		var seen := {}
		for condition in resource.conditions:
			if condition == null:
				return "Condition groups cannot contain empty references."
			if seen.has(condition.id):
				return "Condition groups cannot contain duplicate condition IDs."
			seen[condition.id] = true
			var error := validate(condition)
			if not error.is_empty():
				return error
	elif resource is Interaction:
		if resource.action == null:
			return "An interaction must retain its required action reference."
		var action_error := validate(resource.action)
		if not action_error.is_empty():
			return action_error
		if resource.requirements != null:
			var requirement_error := validate(resource.requirements)
			if not requirement_error.is_empty():
				return requirement_error
		return argument_error(resource, resource.action)
	return ""


static func effect_error(effect: Dictionary) -> String:
	return Contract.effect_error(effect)


static func address_error(definition: Dictionary) -> String:
	return Contract.address_error(definition)


static func argument_error(interaction: Resource, action: Resource) -> String:
	var description := Executors.describe(action.behavior_id)
	if not description["ok"]:
		return description["error"]
	var checked := Contract.validate_arguments(description["value"], action.to_definition(), interaction.arguments)
	return "" if checked["ok"] else "Interaction '%s': %s" % [interaction.id, checked["error"]]


static func protected_key(resource: Resource, path: Array, operation: String) -> bool:
	if path.size() <= 1:
		return true
	var last: Dictionary = path[-1]
	if resource is Action and path.size() == 3 and String(last["text"]) in EFFECT_KEYS:
		return true
	if resource is Condition and path.size() == 2:
		return String(last["text"]) in REQUIREMENT_KEYS or (operation == "rename" and last["text"] == "message")
	return false


static func tree(resource: Resource) -> Dictionary:
	if resource is Behavior:
		return Sequence.tree(resource)
	var state := {"count": 0, "error": ""}
	var root := ValueTree.build(fields(resource), [], "data", true, state, 1 if resource is Automation else 2)
	if not String(state["error"]).is_empty():
		return Values.failure(state["error"])
	_capabilities(resource, root)
	return Values.success(root)


static func _capabilities(resource: Resource, node: Dictionary) -> void:
	var path: Array = node["path"]
	node["can_rename"] = node["mutable"] and path[-1]["kind"] != "index" and not protected_key(resource, path, "rename") if not path.is_empty() else false
	node["can_remove"] = node["mutable"] and not protected_key(resource, path, "remove")
	var description := Executors.describe(resource.behavior_id) if resource is Action else {}
	node["can_add_effect"] = resource is Action and path.size() == 1 and path[0]["text"] == "effects" and description.get("ok", false) and description["value"]["supports_effects"]
	if path.is_empty() or (resource is Action and path.size() == 1):
		node["can_add"] = false
	node["allowed_types"] = []
	node["choices"] = []
	if resource is Automation:
		node["can_add"] = false
		if path.size() == 1:
			var name: String = path[0]["text"]
			node["allowed_types"] = ["float", "int"] if name.ends_with("_seconds") else ["StringName"]
			if name == "trigger":
				node["choices"] = ["interval"]
			elif name == "targeting":
				node["choices"] = ["nearest"]
	if resource is Action and path.size() == 1 and path[0]["text"] == "behavior_id":
		node["allowed_types"] = ["StringName"]
	if resource is Interaction and resource.action != null and path.size() == 2:
		var prepared := Executors.arguments_for(resource.action)
		if prepared["ok"]:
			for spec: Dictionary in prepared["value"]:
				if spec["name"] == path[-1]["text"]:
					node["allowed_types"] = [] if spec["allowed_types"] == ["Variant"] else spec["allowed_types"]
					if spec["required"]:
						node["can_remove"] = false
						node["can_rename"] = false
	if resource is Condition and path.size() == 2:
		var name: String = path[-1]["text"]
		if name == "value":
			node["allowed_types"] = ["int", "float", "bool"]
		elif name in ["entity", "container", "operator", "message"]:
			node["allowed_types"] = ["String", "StringName"]
		if name == "entity":
			node["choices"] = ["actor", "target"]
		elif name == "operator":
			node["choices"] = ["==", "!=", ">", ">=", "<", "<="]
	if resource is Action and path.size() == 3 and String(path[-1]["text"]) in ["operation", "entity", "container", "value_from"]:
		node["allowed_types"] = ["String", "StringName"]
		if path[-1]["text"] == "operation":
			node["choices"] = ["set", "add"]
		elif path[-1]["text"] == "entity":
			node["choices"] = ["actor", "target"]
	for child: Dictionary in node["children"]:
		_capabilities(resource, child)


static func _text(value: Variant, empty: bool = false) -> bool:
	return typeof(value) in [TYPE_STRING, TYPE_STRING_NAME] and (empty or not String(value).is_empty())


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
