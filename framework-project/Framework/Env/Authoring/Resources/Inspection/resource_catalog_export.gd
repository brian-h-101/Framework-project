extends SceneTree
const UnifiedBehavior = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")

const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Actions/action_resource.gd"
)
const ConditionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd"
)
const ConditionGroupResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd"
)
const AutomationResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Automation/automation_resource.gd")

const BehaviorPaths = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")


func _initialize() -> void:
	var result: Dictionary = _export_catalog()

	print("[resource-catalog] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)


func _export_catalog() -> Dictionary:
	var found := BehaviorPaths.resource_paths()
	if not found["ok"]:
		return found

	var resources: Array[Dictionary] = []
	var ids := {}

	for resource_path: String in found["value"]:
		var authored: Resource = ResourceLoader.load(resource_path)

		if authored == null:
			return _failure(
				"Could not load resource: %s" % resource_path
			)

		var kind: String = _kind_for(authored)

		if kind.is_empty():
			continue

		var resource_id: String = String(authored.get("id"))

		if resource_id.is_empty():
			return _failure(
				"Resource ID cannot be empty: %s" % resource_path
			)

		var key := kind + ":" + resource_id
		if ids.has(key):
			return _failure("Duplicate %s ID '%s' in %s and %s." % [kind, resource_id, ids[key], resource_path])
		ids[key] = resource_path
		resources.append({
			"id": resource_id,
			"kind": kind,
			"source_path": resource_path,
		})

	return {
		"ok": true,
		"value": {
			"version": 1,
			"resources": resources,
		},
		"error": "",
	}


func _kind_for(authored: Resource) -> String:
	if authored is UnifiedBehavior:
		return "behavior"
	if authored is AutomationResource:
		return "automation"
	if authored is ActionResource:
		return "action"

	if authored is ConditionResource:
		return "condition"

	if authored is ConditionGroupResource:
		return "condition_group"

	if authored is InteractionResource:
		return "interaction"

	return ""


func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}
