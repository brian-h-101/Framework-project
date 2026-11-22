extends RefCounted

const Schema = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_schema.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Policy = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")


static func paths(seed: String) -> Dictionary:
	if not seed.is_empty():
		var checked := Files.check_path(seed)
		if not checked["ok"]:
			return checked
	var found := PackedStringArray()
	var visited := {}
	var roots := Policy.folders()
	if not roots["ok"]:
		return roots
	var folders: PackedStringArray = roots["value"]
	if not seed.is_empty():
		folders.append(seed.get_base_dir())
	for folder: String in folders:
		var result := _walk(folder, found, visited)
		if not result["ok"]:
			return result
	found.sort()
	return Values.success(found)


static func load_library(seed: String) -> Dictionary:
	var listed := paths(seed)
	if not listed["ok"]:
		return listed
	var resources := {}
	var hashes := {}
	for path: String in listed["value"]:
		var checked := _hash_resources(path, hashes, 0)
		if not checked["ok"]:
			return checked
	for path: String in listed["value"]:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if resource == null:
			return Values.failure("Could not inspect behavior catalogue Resource: %s." % path)
		if not Schema.kind(resource).is_empty():
			resources[path] = resource
	var checked := Files.check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	return Values.success({"resources": resources, "hashes": hashes, "paths": listed["value"]})


static func _hash_resources(path: String, hashes: Dictionary, depth: int) -> Dictionary:
	if hashes.has(path):
		return Values.success(true)
	if depth > 64 or hashes.size() >= 10000:
		return Values.failure("Behavior dependencies exceed 64 levels or 10000 Resources.")
	var checked := Files.check_path(path)
	if not checked["ok"]:
		return checked
	hashes[path] = FileAccess.get_sha256(path)
	for dependency in ResourceLoader.get_dependencies(path):
		var fallback := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
		if dependency.contains("::"):
			var uid := ResourceUID.text_to_id(dependency.get_slice("::", 0))
			if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
				var resolved := ResourceUID.get_id_path(uid)
				if FileAccess.file_exists(resolved):
					fallback = resolved
		if fallback.ends_with(".tres"):
			checked = _hash_resources(fallback, hashes, depth + 1)
			if not checked["ok"]:
				return checked
	return Values.success(true)


static func unchanged(seed: String, expected: Array) -> Dictionary:
	var listed := paths(seed)
	if not listed["ok"]:
		return listed
	return Values.success(true) if Array(listed["value"]) == expected else Values.failure("The behavior catalogue changed. Refresh and retry.")


static func _walk(folder: String, found: PackedStringArray, visited: Dictionary) -> Dictionary:
	if visited.has(folder) or not DirAccess.dir_exists_absolute(folder):
		return Values.success(true)
	visited[folder] = true
	var listed := Paths.paths_in(folder)
	if not listed["ok"]:
		return listed
	for path: String in listed["value"]:
		if not found.has(path):
			found.append(path)
	return Values.success(true)
