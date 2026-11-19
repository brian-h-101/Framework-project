extends RefCounted

const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)


static func compose_in(
	folder_path: String,
	base: Dictionary = {}
) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder_path):
		return _failure(
			"Fragment folder does not exist: %s" % folder_path
		)

	return compose_paths(_fragment_paths_in(folder_path), base)


# Explicit selections retain their authored order.
static func compose_paths(
	script_paths: PackedStringArray,
	base: Dictionary = {}
) -> Dictionary:
	var parts: Array[Dictionary] = [base]

	for script_path in script_paths:
		if not ResourceLoader.exists(script_path):
			return _failure("Fragment script does not exist: %s" % script_path)

		var content_script := ResourceLoader.load(
			script_path,
			"Script"
		) as Script

		if content_script == null:
			return _failure(
				"Could not load fragment script: %s" % script_path
			)

		if not content_script.can_instantiate():
			return _failure(
				"Fragment script could not compile: %s" % script_path
			)

		if not content_script.has_script_method(&"defaults"):
			continue

		if not _has_static_defaults(content_script):
			return _failure(
				"defaults() must be static: %s" % script_path
			)

		var authored: Variant = content_script.call(&"defaults")

		if not authored is Dictionary:
			return _failure(
				"defaults() must return a Dictionary: %s"
				% script_path
			)

		parts.append(authored)

	return {
		"ok": true,
		"value": ContentComposition.combine(parts),
		"error": "",
	}


static func _fragment_paths_in(
	folder_path: String
) -> PackedStringArray:
	var script_paths := PackedStringArray()

	for folder_entry in ResourceLoader.list_directory(folder_path):
		if not folder_entry.ends_with("/"):
			continue

		var child_folder := folder_path.path_join(folder_entry)

		for script_entry in ResourceLoader.list_directory(child_folder):
			if (
				script_entry.ends_with("/")
				or script_entry.get_extension() != "gd"
			):
				continue

			script_paths.append(child_folder.path_join(script_entry))

	script_paths.sort()
	return script_paths


static func _has_static_defaults(content_script: Script) -> bool:
	for method in content_script.get_script_method_list():
		if StringName(method["name"]) == &"defaults":
			return (int(method["flags"]) & METHOD_FLAG_STATIC) != 0

	return false


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
