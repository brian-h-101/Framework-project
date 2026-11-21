extends RefCounted

const FragmentResource = preload("res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd")
const Inspection = preload("res://Framework/Env/Authoring/Attributes/attribute_inspection.gd")
const Collections = preload("res://Framework/Env/Authoring/Shared/collection_editing.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Attributes/attribute_values.gd")


static func edit(path: String, request: Dictionary) -> Dictionary:
	var checked := Inspection.check_path(path)
	if not checked["ok"]:
		return checked
	var expected: Variant = request.get("expected_hash")
	if not expected is String or expected.length() != 64 or not expected.is_valid_hex_number(false):
		return Values.failure("An edit requires the inspected file's SHA-256 hash.")
	if FileAccess.get_sha256(path) != expected:
		return Values.failure("The resource file changed. Refresh and run the edit again.")
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as FragmentResource
	if resource == null:
		return Values.failure("Expected a container fragment Resource: %s" % path)
	var initial_error := FragmentResource.container_error(resource.containers)
	if not initial_error.is_empty():
		return Values.failure(initial_error)
	var containers := resource.containers.duplicate(true)
	var changed := _apply(containers, request)
	if not changed["ok"]:
		return changed
	var described := Inspection.describe(path, expected, containers)
	if not described["ok"]:
		return described
	resource.containers = containers
	return _save(path, expected, resource)


static func _apply(containers: Dictionary, request: Dictionary) -> Dictionary:
	if request.get("operation") == "set" and request.get("path") is Array and request["path"].size() == 1:
		return Values.failure("Use container entry commands to edit a container.")
	var result := Collections.apply(containers, request)
	if not result["ok"]:
		return result
	var error := FragmentResource.container_error(containers)
	return Values.failure(error) if not error.is_empty() else result


static func _save(path: String, expected: String, resource: FragmentResource) -> Dictionary:
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		return Values.failure("Could not generate a staging file name.")
	var staged := path.get_base_dir().path_join(".attribute-pending-" + bytes.hex_encode() + ".tres")
	if FileAccess.file_exists(staged):
		return Values.failure("Attribute staging file already exists.")
	var original_text := FileAccess.get_file_as_string(path)
	var uid := Inspection.resource_uid(path)
	var saved := ResourceSaver.save(resource, staged)
	if saved != OK:
		return _discard(staged, "Could not stage the Resource: %s" % error_string(saved))
	if uid != ResourceUID.INVALID_ID:
		var uid_error := ResourceSaver.set_uid(staged, uid)
		if uid_error != OK:
			return _discard(staged, "Could not preserve the Resource UID.")
	var formatted := Files.format(FileAccess.get_file_as_string(staged), original_text.get_slice("\n", 0).ends_with("\r"))
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return _discard(staged, "Could not format the staged Resource.")
	file.store_string(formatted)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _discard(staged, "Could not write the complete staged Resource.")
	var reloaded := ResourceLoader.load(staged, "", ResourceLoader.CACHE_MODE_IGNORE) as FragmentResource
	if reloaded == null:
		return _discard(staged, "The staged Resource could not reload.")
	if reloaded.containers != resource.containers:
		return _discard(staged, "The staged Resource changed attribute data.")
	if Inspection.resource_uid(staged) != uid:
		return _discard(staged, "The staged Resource changed its UID.")
	var graph := Inspection.describe(path, FileAccess.get_sha256(staged), reloaded.containers)
	if not graph["ok"]:
		return _discard(staged, graph["error"])
	var checked := Inspection.check_path(path)
	if not checked["ok"] or FileAccess.get_sha256(path) != expected:
		return _discard(staged, "The resource file changed before saving. Refresh and try again.")
	var published := DirAccess.rename_absolute(staged, path)
	if published != OK:
		return _discard(staged, "Could not publish the Resource: %s" % error_string(published))
	return graph


static func _discard(path: String, message: String) -> Dictionary:
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		message += " Could not remove staging file: %s" % path
	return Values.failure(message)
