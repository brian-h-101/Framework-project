extends RefCounted

const MovementConfiguration = preload(
	"res://Framework/Env/Configuration/Resources/movement_resource.gd"
)
const Paths = preload("res://Framework/Env/Setup/library_path_policy.gd")
const Document = preload("res://Framework/Env/Authoring/Scenes/scene_document.gd")
const ROOT := "res://Framework/Content/Configuration"
const MAX_BYTES := 8 * 1024 * 1024


static func read() -> Dictionary:
	var found := Paths.paths_in(ROOT)
	if not found["ok"]:
		return found
	var configurations: Array[Dictionary] = []
	for path: String in found["value"]:
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if loaded == null:
			return Document.failure("Could not load configuration: %s." % path)
		if not loaded is MovementConfiguration:
			continue
		var inspected := inspect(path)
		if not inspected["ok"]:
			return inspected
		configurations.append(inspected["value"])
	return Document.success({"version": 1, "configurations": configurations})


static func inspect(path: String) -> Dictionary:
	if path.get_extension() != "tres":
		return Document.failure("Choose a movement configuration .tres resource.")
	var hashes := {}
	var collected := _collect_dependencies(path, hashes, 0)
	if not collected["ok"]:
		return collected
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not loaded is MovementConfiguration:
		return Document.failure("Expected a movement configuration: %s." % path)
	var movement: MovementConfiguration = loaded
	var checked := movement.read()
	if not checked["ok"]:
		return checked
	if String(movement.movement_action.behavior_id).strip_edges().is_empty():
		return Document.failure("Movement Action requires a behavior ID: %s." % path)
	for dependency: String in hashes:
		if FileAccess.get_sha256(dependency) != hashes[dependency]:
			return Document.failure("Movement dependency changed while reading: %s." % dependency)
	return Document.success({
		"source_path": path,
		"action_id": String(movement.movement_action.id),
		"behavior_id": String(movement.movement_action.behavior_id),
		"dependency_hashes": hashes,
	})


static func _collect_dependencies(path: String, hashes: Dictionary, depth: int) -> Dictionary:
	if hashes.has(path):
		return Document.success(true)
	if depth > 64 or hashes.size() >= 1000:
		return Document.failure("Movement dependencies exceed the depth or file limit.")
	var error := Paths.project_error(path)
	if not error.is_empty():
		return Document.failure(error)
	if path.get_extension() not in ["tres", "gd"] or not FileAccess.file_exists(path):
		return Document.failure("Expected an existing .tres or .gd movement dependency: %s." % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Document.failure("Cannot read movement dependency: %s." % path)
	var size := file.get_length()
	file.close()
	if size <= 0 or size > MAX_BYTES:
		return Document.failure("Movement dependencies must contain between 1 byte and 8 MiB.")
	hashes[path] = FileAccess.get_sha256(path)
	for dependency: String in ResourceLoader.get_dependencies(path):
		var resolved := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
		if dependency.contains("::"):
			var uid := ResourceUID.text_to_id(dependency.get_slice("::", 0))
			if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
				var registered := ResourceUID.get_id_path(uid)
				if FileAccess.file_exists(registered):
					resolved = registered
		var collected := _collect_dependencies(resolved, hashes, depth + 1)
		if not collected["ok"]:
			return collected
	return Document.success(true)
