extends RefCounted

const Policy = preload("res://Framework/Env/Setup/Library/authored_library.gd")
const Fragment = preload("res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd")
const Shared = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")


static func fingerprint(path: String) -> String:
	return Shared.fingerprint(path)


static func catalogue() -> Dictionary:
	return Shared.catalogue(Policy.ROOT, Policy.path_error, _describe)


static func _describe(resource: Resource) -> Dictionary:
	return {"supported": resource is Fragment}


static func _snapshot(resource: Resource) -> Dictionary:
	return resource.containers


static func draft(path: String, request: Dictionary) -> Dictionary:
	var error := Policy.resource_error(path)
	if error.is_empty():
		error = Policy.name_error(path.get_file())
	if not error.is_empty():
		return Values.failure(error)
	var container: Variant = request.get("container_name")
	if not container is String or String(container).strip_edges().is_empty() or String(container).to_utf8_buffer().has(0):
		return Values.failure("Enter a nonempty container name.")
	var resource := Fragment.new()
	resource.containers = {StringName(container): {}}
	return Shared.draft(path, request.get("expected_parent"), resource, _snapshot)


static func deletion_preview(path: String, request: Dictionary) -> Dictionary:
	var error := Policy.resource_error(path)
	if not error.is_empty():
		return Values.failure(error)
	var checked := Files.check_path(path)
	if not checked["ok"]:
		return checked
	if not ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) is Fragment:
		return Values.failure("Delete Resource is available only for container fragment .tres files.")
	return Shared.deletion_preview(path, request.get("expected_hash"))
