extends RefCounted

const MovementConfiguration = preload(
	"res://Framework/Content/Universal/Movement/based/Configuration/movement_profile.gd"
)
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")
const Inspection = preload("res://Framework/Env/Authoring/Resources/Configuration/configuration_inspection.gd")
const MAX_BYTES := 8 * 1024 * 1024


static func read() -> Dictionary:
	var found := paths()
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


static func paths() -> Dictionary:
	var found := PackedStringArray()
	for folder: String in [Inspection.PROFILES_ROOT, Inspection.ROOT.trim_suffix("/")]:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		var discovered := Paths.paths_in(folder)
		if not discovered["ok"]:
			return discovered
		found.append_array(discovered["value"])
	found.sort()
	return Document.success(found)


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
	var definition: Dictionary = checked["value"]
	var action_id := String(definition["action_id"])
	var behavior_id := String(definition["behavior_id"])
	if movement.movement_behavior != null:
		action_id = String(definition["velocity_step_id"])
	else:
		behavior_id = String(movement.movement_action.behavior_id)
		if behavior_id.strip_edges().is_empty():
			return Document.failure("Movement Action requires a behavior ID: %s." % path)
	for dependency: String in hashes:
		if FileAccess.get_sha256(dependency) != hashes[dependency]:
			return Document.failure("Movement dependency changed while reading: %s." % dependency)
	return Document.success({
		"source_path": path,
		"action_id": action_id,
		"behavior_id": behavior_id,
		"body_type": movement.resolved_environment().body_type(),
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
	if path.get_extension() == "gd":
		# GDScript base classes and preloaded scripts can be absent from get_dependencies().
		var script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Script
		if script == null:
			return Document.failure("Could not load movement script dependency: %s." % path)
		var related: Array = script.get_script_constant_map().values()
		related.append(script.get_base_script())
		for dependency in related:
			if not dependency is Script:
				continue
			var source: String = dependency.resource_path
			if source.is_empty() or source.contains("::"):
				continue
			var collected := _collect_dependencies(source, hashes, depth + 1)
			if not collected["ok"]:
				return collected
	return Document.success(true)
