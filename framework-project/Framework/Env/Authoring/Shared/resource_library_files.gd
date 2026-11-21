extends RefCounted

const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const IGNORED = [".git", ".godot", "node_modules", "out"]
const REFERENCE_EXTENSIONS = ["tres", "tscn", "res", "scn", "gd", "godot", "gdshader"]


static func catalogue(root: String, path_check: Callable, describe: Callable, extension: String = "tres", file_check: Callable = Callable()) -> Dictionary:
	var error := String(path_check.call(root))
	if not error.is_empty():
		return Values.failure(error)
	var entries: Array = []
	var result := _walk_library(root, "", entries, 0, path_check, describe, extension, file_check)
	return result if not result["ok"] else Values.success({"version": 1, "root_path": root, "entries": entries})


static func target_error(path: String, expected_parent: Variant) -> String:
	var parent := path.get_base_dir()
	if not expected_parent is String or fingerprint(parent) != expected_parent:
		return "The parent directory changed. Refresh and retry."
	var directory := DirAccess.open(parent)
	if directory == null:
		return "The destination directory is unreadable."
	for name in Array(directory.get_directories()) + Array(directory.get_files()):
		if String(name).nocasecmp_to(path.get_file()) == 0:
			return "A file or category with that name already exists."
	return ""


static func draft(path: String, expected_parent: Variant, resource: Resource, snapshot: Callable) -> Dictionary:
	var error := target_error(path, expected_parent)
	if not error.is_empty():
		return Values.failure(error)
	var folder := "res://.godot/authoring/resource_draft_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if DirAccess.dir_exists_absolute(folder) or DirAccess.make_dir_recursive_absolute(folder) != OK:
		return Values.failure("Could not create a unique resource staging directory.")
	var stage := folder.path_join("draft.tres")
	var uid := ResourceUID.create_id()
	if ResourceSaver.save(resource, stage) != OK or ResourceSaver.set_uid(stage, uid) != OK:
		return _discard_draft(stage, Values.failure("Could not save and identify the new Resource."))
	var text := Files.format(FileAccess.get_file_as_string(stage), true)
	var reloaded := ResourceLoader.load(stage, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if reloaded == null or reloaded.get_script() != resource.get_script() or Files.canonical(snapshot.call(reloaded)) != Files.canonical(snapshot.call(resource)) or Files.resource_uid(stage) != uid:
		return _discard_draft(stage, Values.failure("The new Resource failed verification."))
	error = target_error(path, expected_parent)
	return _discard_draft(stage, Values.failure(error) if not error.is_empty() else Values.success({"source_path": path, "source_text": text, "content_hash": text.sha256_text(), "uid": ResourceUID.id_to_text(uid)}))


static func _discard_draft(stage: String, result: Dictionary) -> Dictionary:
	if FileAccess.file_exists(stage) and DirAccess.remove_absolute(stage) != OK:
		return Values.failure("Could not remove the new Resource's staging file.")
	if DirAccess.remove_absolute(stage.get_base_dir()) != OK:
		return Values.failure("Could not remove the new Resource's staging directory.")
	return result


static func verify_snapshot(snapshot: Dictionary, staged: String = "") -> Dictionary:
	for source: String in snapshot["hashes"]:
		if FileAccess.get_sha256(source) != snapshot["hashes"][source]:
			return Values.failure("A project file changed during dependency checking. Retry deletion.")
	for folder: String in snapshot["directories"]:
		var ignored := staged.get_file() if not staged.is_empty() and staged.get_base_dir() == folder else ""
		if fingerprint(folder, ignored) != snapshot["directories"][folder]:
			return Values.failure("Project directories changed during dependency checking. Retry deletion.")
	return Values.success(true)


static func has_literal(text: String, value: String) -> bool:
	return text.contains('"' + value.c_escape() + '"') or text.contains("'" + value.replace("'", "\\'") + "'")


static func fingerprint(path: String, ignored_name: String = "") -> String:
	var directory := DirAccess.open(path)
	if directory == null:
		return ""
	directory.include_hidden = true
	var entries: Array = []
	var names := Array(directory.get_directories()) + Array(directory.get_files())
	names.sort()
	for name: String in names:
		if name == ignored_name:
			continue
		entries.append([name, "link" if directory.is_link(name) else "directory" if directory.dir_exists(name) else "file"])
	return JSON.stringify(entries).sha256_text()


static func _walk_library(path: String, parent: String, entries: Array, depth: int, path_check: Callable, describe: Callable, extension: String, file_check: Callable) -> Dictionary:
	if depth > 64 or entries.size() > 10000:
		return Values.failure("Authored libraries are limited to 64 levels and 10000 entries.")
	var directory := DirAccess.open(path)
	if directory == null:
		return Values.failure("Cannot read authored directory: " + path)
	var before := fingerprint(path)
	entries.append({"source_path": path, "parent_path": parent, "name": path.get_file(), "kind": "root" if parent.is_empty() else "folder", "fingerprint": before, "supported": false})
	var names := Array(directory.get_directories()) + Array(directory.get_files())
	names.sort()
	for name: String in names:
		if name.begins_with("."):
			continue
		var child := path.path_join(name)
		if not String(path_check.call(child)).is_empty():
			entries.append({"source_path": child, "parent_path": path, "name": name, "kind": "blocked", "fingerprint": "", "supported": false})
		elif directory.dir_exists(name):
			var result := _walk_library(child, path, entries, depth + 1, path_check, describe, extension, file_check)
			if not result["ok"]:
				return result
		elif name.get_extension() == extension:
			var checked: Dictionary = file_check.call(child) if file_check.is_valid() else Files.check_path(child)
			if not checked["ok"]:
				return checked
			var hash_before := FileAccess.get_sha256(child)
			var resource := ResourceLoader.load(child, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			if FileAccess.get_sha256(child) != hash_before:
				return Values.failure("Resource changed during discovery: " + child)
			var record := {"source_path": child, "parent_path": path, "name": name, "kind": "resource", "fingerprint": hash_before}
			record.merge(describe.call(resource))
			entries.append(record)
	if fingerprint(path) != before:
		return Values.failure("Authored directory changed during discovery. Refresh and retry.")
	return Values.success(true)


static func deletion_preview(path: String, expected_hash: Variant, file_check: Callable = Callable()) -> Dictionary:
	var checked: Dictionary = file_check.call(path) if file_check.is_valid() else Files.check_path(path)
	if not checked["ok"]:
		return checked
	var hash := FileAccess.get_sha256(path)
	if hash != expected_hash:
		return Values.failure("The selected Resource changed. Refresh and retry.")
	var snapshot := {"hashes": {}, "directories": {}, "consumers": []}
	checked = _scan_references("res://", path, Files.resource_uid(path), snapshot, 0)
	if not checked["ok"]:
		return checked
	for source: String in snapshot["hashes"]:
		if FileAccess.get_sha256(source) != snapshot["hashes"][source]:
			return Values.failure("A project file changed during dependency checking. Retry deletion.")
	for folder: String in snapshot["directories"]:
		if fingerprint(folder) != snapshot["directories"][folder]:
			return Values.failure("Project directories changed during dependency checking. Retry deletion.")
	return Values.success({"source_path": path, "content_hash": hash, "consumers": snapshot["consumers"], "hashes": snapshot["hashes"], "directories": snapshot["directories"]})


static func reference_snapshot() -> Dictionary:
	var snapshot := {"hashes": {}, "directories": {}, "consumers": []}
	var checked := _scan_references("res://", "", ResourceUID.INVALID_ID, snapshot, 0)
	if not checked["ok"]:
		return checked
	snapshot.erase("consumers")
	checked = verify_snapshot(snapshot)
	return {"ok": true, "value": snapshot, "error": ""} if checked["ok"] else checked


static func _scan_references(folder: String, target: String, target_uid: int, snapshot: Dictionary, depth: int) -> Dictionary:
	if depth > 64 or snapshot["directories"].size() > 10000 or snapshot["hashes"].size() > 20000:
		return Values.failure("Dependency scanning exceeded its project size limits.")
	var directory := DirAccess.open(folder)
	if directory == null:
		return Values.failure("Cannot check references in: " + folder)
	directory.include_hidden = true
	snapshot["directories"][folder] = fingerprint(folder)
	for name in directory.get_directories():
		if name in IGNORED:
			continue
		var child := folder.path_join(name)
		if directory.is_link(name):
			return Values.failure("Cannot verify dependencies through a project directory link: " + child)
		if FileAccess.file_exists(child.path_join("project.godot")):
			continue
		var checked := _scan_references(child, target, target_uid, snapshot, depth + 1)
		if not checked["ok"]:
			return checked
	for name in directory.get_files():
		if name.get_extension() not in REFERENCE_EXTENSIONS:
			continue
		var path := folder.path_join(name)
		if directory.is_link(name):
			return Values.failure("Cannot verify a linked project file: " + path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 16 * 1024 * 1024:
			return Values.failure("A project dependency is unreadable or exceeds 16 MiB: " + path)
		file.close()
		snapshot["hashes"][path] = FileAccess.get_sha256(path)
		if target.is_empty() or path == target:
			continue
		var referenced := false
		if name.get_extension() in ["tres", "tscn", "res", "scn"]:
			for dependency in ResourceLoader.get_dependencies(path):
				var fallback := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
				if not fallback.begins_with("res://"):
					fallback = path.get_base_dir().path_join(fallback).simplify_path()
				var dependency_uid := ResourceUID.text_to_id(dependency.get_slice("::", 0)) if dependency.contains("::") else ResourceUID.INVALID_ID
				if fallback == target or (target_uid != ResourceUID.INVALID_ID and dependency_uid == target_uid):
					referenced = true
		if name.get_extension() not in ["res", "scn"]:
			var text := FileAccess.get_file_as_string(path)
			var uid_text := ResourceUID.id_to_text(target_uid) if target_uid != ResourceUID.INVALID_ID else ""
			referenced = referenced or text.contains(target) or (not uid_text.is_empty() and text.contains(uid_text)) or _relative_literal_reference(text, path, target)
		if referenced:
			snapshot["consumers"].append({"source_path": path, "kind": "resource" if name.get_extension() in ["tres", "tscn", "res", "scn"] else "text"})
	return Values.success(true)


static func _relative_literal_reference(text: String, source: String, target: String) -> bool:
	var index := 0
	while index < text.length():
		var quote := text[index]
		index += 1
		if quote not in ["\"", "'"]:
			continue
		var literal := ""
		var escaped := false
		while index < text.length():
			var character := text[index]
			index += 1
			if escaped:
				literal += "\\" + character
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				break
			else:
				literal += character
		var value := literal.c_unescape()
		if value.get_extension() == target.get_extension() and not value.contains(":") and source.get_base_dir().path_join(value).simplify_path() == target:
			return true
	return false
