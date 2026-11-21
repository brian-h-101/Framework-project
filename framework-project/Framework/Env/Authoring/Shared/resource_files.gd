extends RefCounted

const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const MAX_FILE_BYTES = 8 * 1024 * 1024


static func check_path(path: String) -> Dictionary:
	if not path.begins_with("res://") or path.get_extension() != "tres" or path.simplify_path() != path:
		return Values.failure("Choose a project-relative .tres Resource.")
	var relative := path.trim_prefix("res://")
	for part in relative.split("/"):
		if part.is_empty() or part in [".", ".."] or part.contains("\\") or part.contains(":") or part.to_utf8_buffer().has(0):
			return Values.failure("Invalid project Resource path.")
	var directory := DirAccess.open("res://")
	if directory == null:
		return Values.failure("Project directory is unreadable.")
	var current := "res://"
	for part in relative.split("/"):
		current = current.path_join(part)
		if directory.is_link(current):
			return Values.failure("Attribute authoring does not follow symbolic links or junctions.")
	if not FileAccess.file_exists(path):
		return Values.failure("Resource file does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Values.failure("Resource file is unreadable: %s" % path)
	var size := file.get_length()
	file.close()
	if size == 0 or size > MAX_FILE_BYTES:
		return Values.failure("Attribute Resources must contain between 1 byte and 8 MiB.")
	return Values.success(true)


static func resource_uid(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ResourceUID.INVALID_ID
	var header := file.get_line()
	file.close()
	var pattern := RegEx.new()
	pattern.compile("uid=\"([^\"]+)\"")
	var matched := pattern.search(header)
	return ResourceUID.text_to_id(matched.get_string(1)) if matched != null else ResourceUID.INVALID_ID


static func check_hashes(expected: Dictionary, required: Dictionary) -> Dictionary:
	for path in required:
		if not path is String:
			return Values.failure("Resource dependency paths must be text.")
		var checked := check_path(path)
		if not checked["ok"]:
			return checked
		if not expected.get(path) is String or String(expected[path]).length() != 64 or not String(expected[path]).is_valid_hex_number(false) or FileAccess.get_sha256(path) != expected[path]:
			return Values.failure("Resource dependency changed or was not inspected: %s. Refresh and retry." % path)
	return Values.success(true)


static func save(path: String, hashes: Dictionary, resource: Resource, snapshot: Callable, guard: Callable = Callable(), pass_stage: bool = false) -> Dictionary:
	var checked := check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	var random := Crypto.new().generate_random_bytes(16)
	if random.size() != 16:
		return Values.failure("Could not generate a resource staging name.")
	var staged := path.get_base_dir().path_join(".behavior-pending-" + random.hex_encode() + ".tres")
	if FileAccess.file_exists(staged):
		return Values.failure("Resource staging file already exists.")
	var original := FileAccess.get_file_as_string(path)
	var uid := resource_uid(path)
	var saved := ResourceSaver.save(resource, staged)
	if saved != OK:
		return _discard(staged, "Could not stage Resource: %s" % error_string(saved))
	if uid != ResourceUID.INVALID_ID and ResourceSaver.set_uid(staged, uid) != OK:
		return _discard(staged, "Could not preserve the Resource UID.")
	var text := format(FileAccess.get_file_as_string(staged), original.get_slice("\n", 0).ends_with("\r"))
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return _discard(staged, "Could not format the staged Resource.")
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _discard(staged, "Could not write the complete staged Resource.")
	var reloaded := ResourceLoader.load(staged, "", ResourceLoader.CACHE_MODE_IGNORE)
	if reloaded == null or canonical(snapshot.call(reloaded)) != canonical(snapshot.call(resource)) or resource_uid(staged) != uid:
		return _discard(staged, "The staged Resource failed type, value, reference or UID verification.")
	checked = check_hashes(hashes, hashes)
	if not checked["ok"]:
		return _discard(staged, checked["error"])
	if guard.is_valid():
		checked = guard.call(staged) if pass_stage else guard.call()
		if not checked["ok"]:
			return _discard(staged, checked["error"])
	var published := DirAccess.rename_absolute(staged, path)
	if published != OK:
		return _discard(staged, "Could not publish Resource: %s" % error_string(published))
	return Values.success({"source_path": path, "content_hash": FileAccess.get_sha256(path)})


static func canonical(value: Variant) -> Variant:
	if value is Resource:
		return ["Resource", value.get_class(), value.resource_path, value.get_script().resource_path if value.get_script() != null else ""]
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool:
			return str(typeof(left)) + var_to_str(left) < str(typeof(right)) + var_to_str(right)
		)
		var entries: Array = []
		for key in keys:
			entries.append([canonical(key), canonical(value[key])])
		return ["Dictionary", value.get_typed_key_builtin(), value.get_typed_value_builtin(), entries]
	if value is Array:
		var entries: Array = []
		for element in value:
			entries.append(canonical(element))
		return ["Array", value.get_typed_builtin(), entries]
	return [typeof(value), value]


static func _discard(path: String, message: String) -> Dictionary:
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		message += " Could not remove staging file: %s." % path
	return Values.failure(message)


static func format(source: String, crlf: bool) -> String:
	var formatted := ""
	var depth := 0
	var quoted := false
	var escaped := false
	for line in source.split("\n"):
		var starts_in_string := quoted
		var text := line if starts_in_string else line.strip_edges(true, false)
		var indentation := maxi(0, depth - (1 if text.begins_with("}") else 0))
		for character in text:
			if escaped:
				escaped = false
				continue
			if character == "\\" and quoted:
				escaped = true
			elif character == "\"":
				quoted = not quoted
			elif not quoted and character == "{":
				depth += 1
			elif not quoted and character == "}":
				depth -= 1
		if not quoted:
			text = text.strip_edges(false, true)
		formatted += ("\t".repeat(indentation) if not starts_in_string and not text.is_empty() else "") + text
		formatted += "\n" if quoted or not crlf else "\r\n"
	return formatted.strip_edges() + ("\r\n" if crlf else "\n")


