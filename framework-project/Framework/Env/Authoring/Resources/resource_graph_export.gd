extends SceneTree

const InteractionContent = preload(
	"res://Framework/Content/Behavior/Interaction/interactions.gd"
)
const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/action_resource.gd"
)
const ConditionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/condition_resource.gd"
)
const ConditionGroupResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/condition_group_resource.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd"
)

var _nodes: Dictionary[String, Dictionary] = {}


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary

	if arguments.is_empty():
		result = _export_graph()
	elif arguments.size() == 1:
		result = _export_selected_graph(arguments[0])
	else:
		result = _failure(
			"Expected zero arguments or one project-relative .tres path."
		)

	print("[resource-graph] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)


func _export_graph() -> Dictionary:
	var discovered: Dictionary = InteractionContent.definitions()

	if not discovered["ok"]:
		return discovered

	var roots: Array[String] = []
	var sources: Dictionary = discovered["sources"]

	for source_path in sources.values():
		roots.append(String(source_path))

	roots.sort()

	for source_path in roots:
		var authored_root: Resource = ResourceLoader.load(source_path)

		if authored_root == null:
			return _failure(
				"Could not load interaction: %s" % source_path
			)

		var error: String = _collect(authored_root)

		if not error.is_empty():
			return _failure(error)

	return {
		"ok": true,
		"value": {
			"version": 1,
			"roots": roots,
			"nodes": _nodes,
		},
		"error": "",
	}


func _export_selected_graph(resource_path: String) -> Dictionary:
	if (
		not resource_path.begins_with("res://")
		or resource_path.get_extension() != "tres"
		or resource_path.contains("\\")
		or resource_path.simplify_path() != resource_path
	):
		return _failure(
			"Expected a project-relative .tres path: %s"
			% resource_path
		)

	if not FileAccess.file_exists(resource_path):
		return _failure(
			"Resource file does not exist: %s" % resource_path
		)

	var authored_root: Resource = ResourceLoader.load(resource_path)

	if authored_root == null:
		return _failure(
			"Could not load resource: %s" % resource_path
		)

	var error: String = _collect(authored_root)

	if not error.is_empty():
		return _failure(error)

	var roots: Array[String] = [resource_path]

	return {
		"ok": true,
		"value": {
			"version": 1,
			"roots": roots,
			"nodes": _nodes,
		},
		"error": "",
	}


func _collect(authored: Resource) -> String:
	var source_path: String = authored.resource_path

	if (
		not source_path.begins_with("res://")
		or not source_path.ends_with(".tres")
	):
		return "Expected an external .tres resource: %s" % source_path

	if _nodes.has(source_path):
		return ""

	if not (
		authored is InteractionResource
		or authored is ActionResource
		or authored is ConditionGroupResource
		or authored is ConditionResource
	):
		return "Unsupported resource type: %s" % source_path

	var resource_id: String = String(authored.get("id"))

	if resource_id.is_empty():
		return "Resource ID cannot be empty: %s" % source_path

	var record: Dictionary = {
		"id": resource_id,
		"kind": "",
		"source_path": source_path,
		"links": [],
	}

	_nodes[source_path] = record

	if authored is InteractionResource:
		var interaction: InteractionResource = authored as InteractionResource
		record["kind"] = "interaction"

		var action_error: String = _link(
			record,
			"action",
			interaction.action
		)

		if not action_error.is_empty():
			return action_error

		if interaction.requirements != null:
			return _link(
				record,
				"requirements",
				interaction.requirements
			)

	elif authored is ActionResource:
		record["kind"] = "action"

	elif authored is ConditionGroupResource:
		var group: ConditionGroupResource = authored as ConditionGroupResource
		record["kind"] = "condition_group"
		record["operator"] = String(ConditionGroupResource.OPERATOR)

		for condition in group.conditions:
			var condition_error: String = _link(
				record,
				"condition",
				condition
			)

			if not condition_error.is_empty():
				return condition_error

	elif authored is ConditionResource:
		var condition: ConditionResource = authored as ConditionResource
		record["kind"] = "condition"
		record["operator"] = str(condition.requirement.get("operator", ""))
		record["value_text"] = str(condition.requirement.get("value"))

	return ""


func _link(
	parent: Dictionary,
	role: String,
	target: Resource
) -> String:
	if target == null:
		return "Missing %s reference in %s" % [
			role,
			parent["source_path"],
		]

	var error: String = _collect(target)

	if not error.is_empty():
		return error

	parent["links"].append({
		"role": role,
		"target": target.resource_path,
	})

	return ""


func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}
