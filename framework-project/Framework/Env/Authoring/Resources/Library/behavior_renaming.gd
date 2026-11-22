extends RefCounted

const Policy = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")
const Shared = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Schema = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_schema.gd")
const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")


static func preview(source: String, request: Dictionary) -> Dictionary:
	var error := Policy.resource_error(source)
	if not error.is_empty():
		return Values.failure(error)
	var checked := Files.check_path(source)
	if not checked["ok"]:
		return checked
	var name: Variant = request.get("name")
	if not name is String or not Policy.name_error(name).is_empty() or String(name).get_extension() != "tres":
		return Values.failure("Enter a valid .tres filename in the same category.")
	var destination := source.get_base_dir().path_join(name)
	if not Policy.resource_error(destination).is_empty():
		return Values.failure("The rename destination must remain in the Behavior library.")
	error = Shared.target_error(destination, Shared.fingerprint(source.get_base_dir()))
	if not error.is_empty():
		return Values.failure(error)
	if request.get("expected_hash") != FileAccess.get_sha256(source):
		return Values.failure("The selected Resource changed. Refresh and retry.")
	var resource := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource == null or Schema.kind(resource).is_empty():
		return Values.failure("Choose a supported behavior Resource.")
	var scanned := Shared.reference_snapshot()
	if not scanned["ok"]:
		return scanned
	var snapshot: Dictionary = scanned["value"]
	var uid := Files.resource_uid(source)
	var changes: Array[Dictionary] = []
	for path: String in snapshot["hashes"]:
		if path.get_extension() in ["res", "scn"]:
			for dependency in ResourceLoader.get_dependencies(path):
				var fallback := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
				if (fallback == source or (uid != ResourceUID.INVALID_ID and dependency.get_slice("::", 0) == ResourceUID.id_to_text(uid))):
					return Values.failure("Rename cannot update binary consumer: " + path)
			continue
		var text := FileAccess.get_file_as_bytes(path).get_string_from_utf8()
		var rewritten := _rewrite(text, path, source, destination, "" if uid == ResourceUID.INVALID_ID else ResourceUID.id_to_text(uid))
		if not rewritten["ok"]:
			return rewritten
		if rewritten["value"] != text:
			if path.get_extension() == "gdshader":
				return Values.failure("Rename cannot update shader consumer: " + path)
			changes.append({"source_path": path, "source_text": rewritten["value"]})
	checked = Shared.verify_snapshot(snapshot)
	if not checked["ok"]:
		return checked
	return Values.success({"source_path": source, "destination_path": destination, "id": String(resource.id),
		"uid": "" if uid == ResourceUID.INVALID_ID else ResourceUID.id_to_text(uid),
		"changes": changes, "hashes": snapshot["hashes"], "directories": snapshot["directories"]})


static func rename_resource(source: String, request: Dictionary) -> Dictionary:
	var prepared := preview(source, request)
	if not prepared["ok"]:
		return prepared
	var plan: Dictionary = prepared["value"]
	if not request.get("expected_snapshot") is Dictionary or request["expected_snapshot"] != {"hashes": plan["hashes"], "directories": plan["directories"]}:
		return Values.failure("Project references changed. Preview the rename again.")
	var destination: String = plan["destination_path"]
	var stage := "res://.godot/authoring/rename_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if DirAccess.make_dir_recursive_absolute(stage) != OK:
		return Values.failure("Could not create a rename staging directory.")
	var originals := {}
	var stages: Array[String] = []
	for change: Dictionary in plan["changes"]:
		var path: String = change["source_path"]
		originals[path] = FileAccess.get_file_as_bytes(path)
		var staged := stage.path_join(str(stages.size()) + ".txt")
		stages.append(staged)
		if not _write(staged, String(change["source_text"]).to_utf8_buffer()):
			_cleanup(stage, stages)
			return Values.failure("Could not stage the complete reference updates.")
	var checked := Shared.verify_snapshot(plan)
	if not checked["ok"]:
		_cleanup(stage, stages)
		return checked
	if FileAccess.file_exists(destination) or DirAccess.rename_absolute(source, destination) != OK:
		_cleanup(stage, stages)
		return Values.failure("Could not rename the selected Resource without overwriting another file.")
	var uid := Files.resource_uid(destination)
	_update_uid(uid, destination)
	var published: Array[Dictionary] = []
	var error := ""
	for index in plan["changes"].size():
		var change: Dictionary = plan["changes"][index]
		var path: String = destination if change["source_path"] == source else change["source_path"]
		if FileAccess.get_sha256(path) != plan["hashes"][change["source_path"]] or DirAccess.rename_absolute(stages[index], path) != OK:
			error = "A consumer changed or could not be published: " + path
			break
		published.append(change)
	if error.is_empty():
		var reloaded := ResourceLoader.load(destination, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if reloaded == null or String(reloaded.id) != plan["id"] or Files.resource_uid(destination) != uid:
			error = "The renamed Resource failed identity verification."
		for change: Dictionary in published:
			var path: String = destination if change["source_path"] == source else change["source_path"]
			if path.get_extension() in ["tres", "tscn", "gd"]:
				var consumer := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
				if consumer == null or (consumer is GDScript and consumer.reload() != OK):
					error = "A renamed consumer failed verification: " + path
			if path.get_extension() == "godot" and ConfigFile.new().load(path) != OK:
				error = "A renamed configuration failed verification: " + path
	if not error.is_empty():
		# Roll back only bytes still owned by this operation; never overwrite an external edit.
		for change: Dictionary in published:
			var path: String = destination if change["source_path"] == source else change["source_path"]
			if FileAccess.get_sha256(path) == String(change["source_text"]).sha256_text():
				if not _write(path, originals[change["source_path"]]):
					error += " Could not restore " + path
			else:
				error += " An external edit needs review at " + path
		if not FileAccess.file_exists(source) and FileAccess.get_sha256(destination) == plan["hashes"][source] and DirAccess.rename_absolute(destination, source) == OK:
			_update_uid(uid, source)
		else:
			error += " Resource location needs review: " + destination
	_cleanup(stage, stages)
	return Values.failure(error) if not error.is_empty() else Values.success({"source_path": source,
		"destination_path": destination, "id": plan["id"], "uid": plan["uid"], "updated_files": plan["changes"].size()})


static func _rewrite(text: String, consumer: String, source: String, destination: String, uid_text: String) -> Dictionary:
	var edits: Array[Dictionary] = []
	var allowed_uids := {}
	var protected_fields: Array[Dictionary] = []
	if text.contains(source) and consumer.get_extension() in ["tres", "tscn"]:
		var parsed := Document.parse(text)
		if not parsed["ok"]:
			return Values.failure("Cannot inspect Resource identity fields in " + consumer)
		for section: Dictionary in parsed["value"]["sections"]:
			for property: Dictionary in section["properties"]:
				if property["name"] == "resource_name" or property["name"] == "id" or String(property["name"]).ends_with("_id"):
					protected_fields.append(property)
	if not uid_text.is_empty() and text.contains(uid_text) and consumer.get_extension() in ["tres", "tscn"]:
		var parsed := Document.parse(text)
		if not parsed["ok"]:
			return Values.failure("Cannot inspect UID references in " + consumer)
		for section: Dictionary in parsed["value"]["sections"]:
			var field: Dictionary = section["attributes"].get("uid", {})
			var path := Document.attribute(section, "path")
			if not path.begins_with("res://"):
				path = consumer.get_base_dir().path_join(path).simplify_path()
			if Document.attribute(section, "uid") == uid_text and ((consumer == source and section["tag"] == "gd_resource") or (section["tag"] == "ext_resource" and path == source)):
				allowed_uids[field["start"]] = true
	var cursor := 0
	while cursor < text.length():
		var character := text[cursor]
		if character == "#" or (character == ";" and consumer.get_extension() != "gd") or text.substr(cursor, 2) == "//":
			var end := text.find("\n", cursor)
			cursor = text.length() if end == -1 else end + 1
			continue
		if text.substr(cursor, 2) == "/*":
			var end := text.find("*/", cursor + 2)
			cursor = text.length() if end == -1 else end + 2
			continue
		if character not in ["\"", "'"]:
			cursor += 1
			continue
		var start := cursor
		var delimiter: String = character.repeat(3) if text.substr(cursor, 3) == character.repeat(3) else character
		cursor += delimiter.length()
		var first := cursor
		while cursor < text.length():
			if text[cursor] == "\\":
				cursor += 2
			elif text.substr(cursor, delimiter.length()) == delimiter:
				break
			else:
				cursor += 1
		if cursor >= text.length():
			return Values.failure("Cannot safely inspect quoted references in " + consumer)
		var value := text.substr(first, cursor - first).c_unescape()
		cursor += delimiter.length()
		var protected := false
		for field: Dictionary in protected_fields:
			if start >= field["value_start"] and cursor <= field["value_end"]:
				if field["name"] != "resource_name" and (value == source or value.begins_with(source + "::")):
					return Values.failure("Rename found an ambiguous path-shaped authored ID in " + consumer)
				protected = true
		if protected:
			continue
		if not uid_text.is_empty() and (value == uid_text or value.begins_with(uid_text + "::")) and not allowed_uids.has(start):
			return Values.failure("Rename cannot safely update a UID-only consumer: " + consumer)
		var matches := value == source or value.begins_with(source + "::")
		if not value.contains(":") and value.get_extension() == "tres":
			var points_to_source := consumer.get_base_dir().path_join(value).simplify_path() == source
			if points_to_source and consumer.get_extension() == "gd":
				var preload_call := RegEx.new()
				preload_call.compile("\\bpreload\\s*\\(\\s*$")
				matches = preload_call.search(text.substr(0, start)) != null
			elif points_to_source and consumer.get_extension() in ["tres", "tscn"]:
				var parsed := Document.parse(text)
				if not parsed["ok"]:
					return Values.failure("Cannot inspect relative references in " + consumer)
				for section: Dictionary in parsed["value"]["sections"]:
					var field: Dictionary = section["attributes"].get("path", {})
					if section["tag"] == "ext_resource" and field.get("start", -1) == start:
						matches = true
		if matches:
			var replacement := destination + value.trim_prefix(source) if value.begins_with(source) else destination
			var escaped := replacement.c_escape().replace("'", "\\'") if character == "'" else replacement.c_escape()
			edits.append({"start": start, "end": cursor, "text": character + escaped + character})
		elif value.contains(source):
			return Values.failure("Rename found an unsupported composed path in " + consumer)
	return Document.apply(text, edits)


static func _update_uid(uid: int, path: String) -> void:
	if uid != ResourceUID.INVALID_ID:
		if ResourceUID.has_id(uid):
			ResourceUID.set_id(uid, path)
		else:
			ResourceUID.add_id(uid, path)


static func _write(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok


static func _cleanup(stage: String, files: Array[String]) -> void:
	for path in files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(stage)
