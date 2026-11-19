extends RefCounted


static func definitions_in(folder_path: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder_path):
		return _failure(
			"Content folder does not exist: %s" % folder_path
		)

	return _definitions_from_paths(_script_paths_in(folder_path))


static func entity_definitions_in(folder_path: String) -> Dictionary:
	return starting_definitions_in(PackedStringArray([folder_path]))


static func starting_definitions_in(
	folder_paths: PackedStringArray
) -> Dictionary:
	var script_paths := PackedStringArray()

	for folder_path in folder_paths:
		if not DirAccess.dir_exists_absolute(folder_path):
			return _failure(
				"Starting definition folder does not exist: %s"
				% folder_path
			)

		for entry in ResourceLoader.list_directory(folder_path):
			if not entry.ends_with("/"):
				continue

			var preset_path := folder_path.path_join(entry).path_join(
				"starting_attributes.gd"
			)
			if ResourceLoader.exists(preset_path):
				script_paths.append(preset_path)

	return _definitions_from_paths(script_paths)


static func _script_paths_in(folder_path: String) -> PackedStringArray:
	var script_paths := PackedStringArray()

	for entry in ResourceLoader.list_directory(folder_path):
		if entry.ends_with("/") or entry.get_extension() != "gd":
			continue

		script_paths.append(folder_path.path_join(entry))

	return script_paths


static func _definitions_from_paths(
	script_paths: PackedStringArray
) -> Dictionary:
	var definitions: Array[Dictionary] = []
	var sources: Dictionary[StringName, String] = {}
	script_paths.sort()

	for script_path in script_paths:
		var content_script := ResourceLoader.load(
			script_path,
			"Script"
		) as Script

		if content_script == null:
			return _failure(
				"Could not load content script: %s" % script_path
			)

		if not content_script.can_instantiate():
			return _failure(
				"Content script could not compile: %s" % script_path
			)

		if not content_script.has_script_method(&"definition"):
			continue

		if not _has_static_definition(content_script):
			return _failure(
				"definition() must be static: %s" % script_path
			)

		var authored: Variant = content_script.call(&"definition")

		if not authored is Dictionary:
			return _failure(
				"definition() must return a Dictionary: %s"
				% script_path
			)

		var definition: Dictionary = authored

		if definition.get("ok", true) == false:
			var error_message := String(
				definition.get("error", "Unknown composition error.")
			)

			return _failure(
				"Definition failed in %s: %s"
				% [script_path, error_message]
			)

		var authored_id: Variant = definition.get("id")

		if not (authored_id is String or authored_id is StringName):
			return _failure(
				"Definition requires a text ID: %s" % script_path
			)

		var definition_id := StringName(authored_id)

		if definition_id == &"":
			return _failure(
				"Definition ID cannot be empty: %s" % script_path
			)

		if sources.has(definition_id):
			return _failure(
				"Duplicate ID '%s' in %s and %s."
				% [
					definition_id,
					sources[definition_id],
					script_path,
				]
			)

		sources[definition_id] = script_path
		definitions.append(definition)

	return {
		"ok": true,
		"value": definitions,
		"sources": sources,
		"error": "",
	}


static func _has_static_definition(content_script: Script) -> bool:
	for method in content_script.get_script_method_list():
		if StringName(method["name"]) == &"definition":
			return (int(method["flags"]) & METHOD_FLAG_STATIC) != 0

	return false


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
