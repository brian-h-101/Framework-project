extends RefCounted

const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd"
)


static func definitions_in(
	folder_path: String,
	definition_type: Script
) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder_path):
		return _failure(
			"Resource folder does not exist: %s" % folder_path
		)

	var resource_paths: PackedStringArray = []

	for entry in ResourceLoader.list_directory(folder_path):
		if entry.ends_with("/") or entry.get_extension() != "tres":
			continue

		resource_paths.append(folder_path.path_join(entry))

	resource_paths.sort()

	var definitions: Array[Dictionary] = []
	var sources: Dictionary[StringName, String] = {}

	for resource_path in resource_paths:
		var authored: Resource = ResourceLoader.load(resource_path)

		if authored == null:
			return _failure(
				"Could not load resource: %s" % resource_path
			)

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

		var converted: Variant = authored.call(&"to_definition")

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
