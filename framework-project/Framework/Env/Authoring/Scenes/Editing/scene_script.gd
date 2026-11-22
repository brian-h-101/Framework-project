extends RefCounted

const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")


static func inspect(path: String, node_type: String) -> Dictionary:
	if not ClassDB.class_exists(node_type) or not ClassDB.is_parent_class(node_type, "Node"):
		return Document.failure("Choose a native Godot node for the script.")
	var hashes := {}
	var collected := _collect(path, hashes, 0)
	if not collected["ok"]:
		return collected
	var script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Script
	if script == null or not script.can_instantiate():
		return Document.failure("Choose a valid instantiable GDScript: %s." % path)
	# GDScript inheritance is not always reported by ResourceLoader dependencies.
	var base_script: Script = script.get_base_script()
	var bases := {}
	while base_script != null:
		var base_path := base_script.resource_path
		if bases.has(base_path) or bases.size() >= 64:
			return Document.failure("Script inheritance exceeds its depth limit.")
		bases[base_path] = true
		collected = _collect(base_path, hashes, 0)
		if not collected["ok"]:
			return collected
		base_script = base_script.get_base_script()
	var base_type := script.get_instance_base_type()
	if not ClassDB.is_parent_class(node_type, base_type):
		return Document.failure("Script extends %s and cannot attach to %s: %s." % [base_type, node_type, path])
	for dependency: String in hashes:
		if FileAccess.get_sha256(dependency) != hashes[dependency]:
			return Document.failure("Script dependency changed while inspecting: %s." % dependency)
	return Document.success({"script_path": path, "base_type": String(base_type), "dependency_hashes": hashes})


static func _collect(path: String, hashes: Dictionary, depth: int) -> Dictionary:
	if hashes.has(path):
		return Document.success(true)
	if depth > 64 or hashes.size() >= 1000:
		return Document.failure("Script dependencies exceed their depth or file limit.")
	var error := Paths.project_error(path)
	if not error.is_empty():
		return Document.failure(error)
	if path.get_extension() != "gd" or not FileAccess.file_exists(path):
		return Document.failure("Choose an existing project .gd script: %s." % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Document.failure("Cannot read script: %s." % path)
	var size := file.get_length()
	file.close()
	if size <= 0 or size > 8 * 1024 * 1024:
		return Document.failure("Scripts must contain between 1 byte and 8 MiB.")
	hashes[path] = FileAccess.get_sha256(path)
	for dependency: String in ResourceLoader.get_dependencies(path):
		var resolved := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
		if dependency.contains("::"):
			var uid := ResourceUID.text_to_id(dependency.get_slice("::", 0))
			if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
				var registered := ResourceUID.get_id_path(uid)
				if FileAccess.file_exists(registered):
					resolved = registered
		if resolved.get_extension() == "gd":
			var collected := _collect(resolved, hashes, depth + 1)
			if not collected["ok"]:
				return collected
	return Document.success(true)
