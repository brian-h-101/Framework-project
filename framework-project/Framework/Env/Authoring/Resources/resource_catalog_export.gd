extends SceneTree

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

const CONTENT_FOLDERS: Array[String] = [
	"res://Framework/Content/Behavior/Action",
	"res://Framework/Content/Behavior/Condition",
	"res://Framework/Content/Behavior/Interaction",
]


func _initialize() -> void:
	var result: Dictionary = _export_catalog()

	print("[resource-catalog] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)


func _export_catalog() -> Dictionary:
	var resource_paths: PackedStringArray = []

	for folder_path in CONTENT_FOLDERS:
		if not DirAccess.dir_exists_absolute(folder_path):
			return _failure(
				"Resource folder does not exist: %s" % folder_path
			)

		resource_paths.append_array(_paths_in(folder_path))

	resource_paths.sort()

	var resources: Array[Dictionary] = []

	for resource_path in resource_paths:
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


func _paths_in(folder_path: String) -> PackedStringArray:
	var paths: PackedStringArray = []

	for entry in ResourceLoader.list_directory(folder_path):
		var entry_path: String = folder_path.path_join(entry)

		if entry.ends_with("/"):
			paths.append_array(_paths_in(entry_path))
		elif entry.get_extension() == "tres":
			paths.append(entry_path)

	return paths


func _kind_for(authored: Resource) -> String:
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