extends RefCounted

const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Schema = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_schema.gd")
const Executors = preload("res://Framework/Env/Authoring/Resources/Inspection/executor_catalog.gd")

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


static func add_condition(
	group_path: String,
	condition_path: String
) -> Dictionary:
	for source_path in [group_path, condition_path]:
		var path_error: String = _path_error(source_path)

		if not path_error.is_empty():
			return _failure(path_error)

	var hashes := _hashes([group_path, condition_path])

	var loaded_group: Resource = ResourceLoader.load(
		group_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded_group is ConditionGroupResource):
		return _failure(
			"Expected a condition group: %s" % group_path
		)

	var loaded_condition: Resource = ResourceLoader.load(
		condition_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded_condition is ConditionResource):
		return _failure(
			"Expected a condition: %s" % condition_path
		)

	var group: ConditionGroupResource = (
		loaded_group as ConditionGroupResource
	)
	var condition: ConditionResource = (
		loaded_condition as ConditionResource
	)

	if String(group.id).is_empty():
		return _failure(
			"Condition group ID cannot be empty: %s" % group_path
		)

	if String(condition.id).is_empty():
		return _failure(
			"Condition ID cannot be empty: %s" % condition_path
		)

	for existing in group.conditions:
		if existing == null:
			return _failure(
				"Condition group contains an empty reference: %s"
				% group_path
			)

		if (
			existing.resource_path == condition.resource_path
			or existing.id == condition.id
		):
			return _failure(
				"Condition '%s' is already assigned to group '%s'."
				% [condition.id, group.id]
			)

	group.conditions.append(condition)

	var saved := Files.save(group_path, hashes, group, Schema.snapshot)
	if not saved["ok"]:
		return saved

	return {
		"ok": true,
		"value": {
			"group_path": group_path,
			"condition_path": condition_path,
			"condition_count": group.conditions.size(),
		},
		"error": "",
	}


static func set_requirements(
	interaction_path: String,
	group_path: String
) -> Dictionary:
	for source_path in [interaction_path, group_path]:
		var path_error: String = _path_error(source_path)

		if not path_error.is_empty():
			return _failure(path_error)

	var hashes := _hashes([interaction_path, group_path])

	var loaded_interaction: Resource = ResourceLoader.load(
		interaction_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded_interaction is InteractionResource):
		return _failure(
			"Expected an interaction: %s" % interaction_path
		)

	var loaded_group: Resource = ResourceLoader.load(
		group_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded_group is ConditionGroupResource):
		return _failure(
			"Expected a condition group: %s" % group_path
		)

	var interaction: InteractionResource = (
		loaded_interaction as InteractionResource
	)
	var group: ConditionGroupResource = (
		loaded_group as ConditionGroupResource
	)

	if String(interaction.id).is_empty():
		return _failure(
			"Interaction ID cannot be empty: %s" % interaction_path
		)

	if String(group.id).is_empty():
		return _failure(
			"Condition group ID cannot be empty: %s" % group_path
		)

	if group.conditions.has(null):
		return _failure(
			"Condition group contains an empty reference: %s"
			% group_path
		)

	var existing: ConditionGroupResource = interaction.requirements

	if existing != null and (
		existing.resource_path == group.resource_path
		or existing.id == group.id
	):
		return _failure(
			"Condition group '%s' is already assigned to interaction '%s'."
			% [group.id, interaction.id]
		)

	interaction.requirements = group

	var saved := Files.save(interaction_path, hashes, interaction, Schema.snapshot)
	if not saved["ok"]:
		return saved

	return {
		"ok": true,
		"value": {
			"interaction_path": interaction_path,
			"group_path": group_path,
		},
		"error": "",
	}


static func set_action(
	interaction_path: String,
	action_path: String
) -> Dictionary:
	for source_path in [interaction_path, action_path]:
		var path_error: String = _path_error(source_path)

		if not path_error.is_empty():
			return _failure(path_error)

	var hashes := _hashes([interaction_path, action_path])

	var loaded_interaction: Resource = ResourceLoader.load(
		interaction_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded_interaction is InteractionResource):
		return _failure(
			"Expected an interaction: %s" % interaction_path
		)

	var loaded_action: Resource = ResourceLoader.load(
		action_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded_action is ActionResource):
		return _failure(
			"Expected an action: %s" % action_path
		)

	var interaction: InteractionResource = (
		loaded_interaction as InteractionResource
	)
	var action: ActionResource = (
		loaded_action as ActionResource
	)

	if String(interaction.id).is_empty():
		return _failure(
			"Interaction ID cannot be empty: %s" % interaction_path
		)

	if String(action.id).is_empty():
		return _failure(
			"Action ID cannot be empty: %s" % action_path
		)

	var existing: ActionResource = interaction.action

	if existing != null and (
		existing.resource_path == action.resource_path
		or existing.id == action.id
	):
		return _failure(
			"Action '%s' is already assigned to interaction '%s'."
			% [action.id, interaction.id]
		)

	interaction.action = action

	var catalog := Executors.refresh()
	if not catalog["ok"]:
		return catalog
	var error := Schema.validate(interaction)
	if not error.is_empty():
		return _failure(error)
	var saved := Files.save(interaction_path, hashes, interaction, Schema.snapshot, Executors.unchanged_at_stage.bind(catalog["value"]["executor_snapshot"]), true)
	if not saved["ok"]:
		return saved

	return {
		"ok": true,
		"value": {
			"interaction_path": interaction_path,
			"action_path": action_path,
		},
		"error": "",
	}


static func resolve_interaction_source(
	interaction_path: String,
	source_path: String
) -> Dictionary:
	for candidate_path in [interaction_path, source_path]:
		var path_error: String = _path_error(candidate_path)

		if not path_error.is_empty():
			return _failure(path_error)

	var loaded_interaction: Resource = ResourceLoader.load(
		interaction_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	if not (loaded_interaction is InteractionResource):
		return _failure(
			"Expected an interaction: %s" % interaction_path
		)

	var loaded_source: Resource = ResourceLoader.load(
		source_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)

	var source_kind: String = ""

	if loaded_source is ActionResource:
		source_kind = "action"
	elif loaded_source is ConditionGroupResource:
		source_kind = "condition_group"
	else:
		return _failure(
			"Expected an action or condition group: %s"
			% source_path
		)

	return {
		"ok": true,
		"value": {
			"interaction_path": interaction_path,
			"source_path": source_path,
			"kind": source_kind,
		},
		"error": "",
	}


static func _path_error(source_path: String) -> String:
	if (
		not source_path.begins_with("res://")
		or source_path.get_extension() != "tres"
		or source_path.contains("\\")
		or source_path.simplify_path() != source_path
	):
		return "Expected a project-relative .tres path: %s" % source_path

	if not FileAccess.file_exists(source_path):
		return "Resource file does not exist: %s" % source_path

	return ""


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}


static func _hashes(paths: Array) -> Dictionary:
	var hashes := {}
	for path: String in paths:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes
