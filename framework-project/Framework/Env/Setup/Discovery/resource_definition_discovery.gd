extends RefCounted

const BehaviorResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")

const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const BehaviorPaths = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")

const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd"
)
const ActionResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Actions/action_resource.gd")
const ConditionResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd")
const GroupResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd")
const AutomationResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Automation/automation_resource.gd"
)


static func definitions_in(
	folder_path: String,
	definition_type: Script
) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder_path):
		return _failure(
			"Resource folder does not exist: %s" % folder_path
		)

	var listed := Paths.paths_in(folder_path)
	if not listed["ok"]:
		return listed
	return _definitions(listed["value"], definition_type)


static func profile_definitions(definition_type: Script) -> Dictionary:
	var listed := BehaviorPaths.resource_paths()
	return _definitions(listed["value"], definition_type) if listed["ok"] else listed


static func _definitions(resource_paths: PackedStringArray, definition_type: Script) -> Dictionary:

	var definitions: Array[Dictionary] = []
	var sources: Dictionary[StringName, String] = {}
	var all_ids := {}

	for resource_path in resource_paths:
		var authored: Resource = ResourceLoader.load(resource_path)

		if authored == null:
			return _failure(
				"Could not load resource: %s" % resource_path
			)
		var kind := ""

		if authored is BehaviorResource:
			kind = "behavior"
		elif authored is ActionResource:
			kind = "action"
		elif authored is InteractionResource:
			kind = "interaction"
		elif authored is ConditionResource:
			kind = "condition"
		elif authored is GroupResource:
			kind = "condition_group"
		elif authored is AutomationResource:
			kind = "automation"

		if not kind.is_empty():
			var id := String(authored.get("id"))
			if id.strip_edges().is_empty():
				return _failure("Definition ID cannot be empty: " + resource_path)
			var key := kind + ":" + id
			if all_ids.has(key):
				return _failure("Duplicate %s ID '%s' in %s and %s." % [kind, id, all_ids[key], resource_path])
			all_ids[key] = resource_path
		if authored is ActionResource and String(authored.behavior_id).strip_edges().is_empty():
			return _failure("Action behavior ID cannot be empty: " + resource_path)

		if not is_instance_of(authored, definition_type):
			continue

		if not authored.has_method(&"to_definition"):
			return _failure(
				"Resource requires to_definition(): %s"
				% resource_path
			)

		var interaction := authored as InteractionResource

		if interaction != null:
			if interaction.action == null:
				return _failure(
					"Interaction has no action: %s"
					% resource_path
				)

			if interaction.requirements != null:
				if interaction.requirements.conditions.has(null):
					return _failure(
						"Interaction has a missing condition: %s"
						% resource_path
					)

		var converted: Variant

		if authored is AutomationResource or authored is BehaviorResource:
			var checked: Dictionary = authored.read()

			if not checked["ok"]:
				return _failure(
					"Automation validation failed in %s: %s"
					% [resource_path, checked["error"]]
				)

			converted = checked["value"]
		else:
			converted = authored.call(&"to_definition")

		if not converted is Dictionary:
			return _failure(
				"to_definition() must return a Dictionary: %s"
				% resource_path
			)

		var definition: Dictionary = converted
		var authored_id: Variant = definition.get("id")

		if not (
			authored_id is String
			or authored_id is StringName
		):
			return _failure(
				"Definition requires a text ID: %s"
				% resource_path
			)

		var definition_id: StringName = StringName(authored_id)

		if definition_id == &"":
			return _failure(
				"Definition ID cannot be empty: %s"
				% resource_path
			)

		if sources.has(definition_id):
			return _failure(
				"Duplicate ID '%s' in %s and %s."
				% [
					definition_id,
					sources[definition_id],
					resource_path,
				]
			)

		sources[definition_id] = resource_path
		definitions.append(definition)

	return {
		"ok": true,
		"value": definitions,
		"sources": sources,
		"error": "",
	}


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}
