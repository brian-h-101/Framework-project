extends RefCounted

const ContainerFragmentResource = preload(
	"res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd"
)
const ContentComposition = preload(
	"res://Framework/Env/Setup/content_composition.gd"
)


static func compose_in(folder_path: String, base: Dictionary = {}) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder_path):
		return _failure("Fragment folder does not exist: %s" % folder_path)
	return compose_paths(_fragment_paths_in(folder_path), base)


static func compose_paths(
	resource_paths: PackedStringArray,
	base: Dictionary = {}
) -> Dictionary:
	var fragments: Array[ContainerFragmentResource] = []
	for resource_path in resource_paths:
		if resource_path.get_extension() != "tres":
			return _failure("Expected a .tres fragment resource: %s" % resource_path)
		if not ResourceLoader.exists(resource_path):
			return _failure("Fragment resource does not exist: %s" % resource_path)
		var fragment: Resource = ResourceLoader.load(resource_path)
		if not fragment is ContainerFragmentResource:
			return _failure("Expected a container fragment resource: %s" % resource_path)
		fragments.append(fragment as ContainerFragmentResource)
	return compose_resources(fragments, base)


static func compose_resources(
	fragments: Array[ContainerFragmentResource],
	base: Dictionary = {}
) -> Dictionary:
	var base_error := ContainerFragmentResource.container_error(base)
	if not base_error.is_empty():
		return _failure("Invalid composition base: %s" % base_error)
	var parts: Array[Dictionary] = [base]
	for index in fragments.size():
		var fragment := fragments[index]
		if fragment == null:
			return _failure("Missing container fragment resource at index %d." % index)
		var converted := fragment.to_containers()
		if not converted["ok"]:
			return _failure(
				"Invalid fragment %s: %s" % [fragment.resource_path, converted["error"]]
			)
		parts.append(converted["value"])
	return {"ok": true, "value": ContentComposition.combine(parts), "error": ""}


static func _fragment_paths_in(folder_path: String) -> PackedStringArray:
	var resource_paths := PackedStringArray()
	for folder_entry in ResourceLoader.list_directory(folder_path):
		if not folder_entry.ends_with("/"):
			continue
		var child_folder := folder_path.path_join(folder_entry)
		for resource_entry in ResourceLoader.list_directory(child_folder):
			if not resource_entry.ends_with("/") and resource_entry.get_extension() == "tres":
				resource_paths.append(child_folder.path_join(resource_entry))
	resource_paths.sort()
	return resource_paths


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
