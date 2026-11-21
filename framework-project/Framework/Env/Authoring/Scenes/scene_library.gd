extends RefCounted

const Paths = preload("res://Framework/Env/Setup/library_path_policy.gd")
const Shared = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Graph = preload("res://Framework/Env/Authoring/Scenes/scene_graph.gd")
const Templates = preload("res://Framework/Env/Authoring/Scenes/scene_templates.gd")
const ROOTS = ["res://Framework/Content/Maps", "res://Framework/Content/Presentation", "res://Framework/Content/UI/HUD"]


static func path_error(path: String) -> String:
	for root: String in ROOTS:
		if path == root or path.begins_with(root + "/"):
			return Paths.project_error(path)
	return "Choose a path inside Maps, Presentation, or UI/HUD."


static func check_scene(path: String) -> Dictionary:
	var error := path_error(path)
	if not error.is_empty():
		return Values.failure(error)
	if path.get_extension() != "tscn":
		return Values.failure("Choose a .tscn scene file.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Values.failure("Scene file is unreadable: " + path)
	var size := file.get_length()
	file.close()
	return Values.success(true) if size > 0 and size <= 8 * 1024 * 1024 else Values.failure("Scenes must contain between 1 byte and 8 MiB.")


static func catalogue() -> Dictionary:
	var entries: Array = []
	for root: String in ROOTS:
		var listed := Shared.catalogue(root, path_error, _describe, "tscn", check_scene)
		if not listed["ok"]:
			return listed
		entries.append_array(listed["value"]["entries"])
		if entries.size() > 10000:
			return Values.failure("Scene libraries are limited to 10000 entries.")
	return Values.success({"version": 1, "root_paths": ROOTS, "entries": entries})


static func _describe(resource: Resource) -> Dictionary:
	return {"supported": resource is PackedScene}


static func draft(path: String, request: Dictionary) -> Dictionary:
	var error := path_error(path)
	if error.is_empty() and path.get_extension() != "tscn":
		error = "Use a .tscn filename."
	if error.is_empty():
		error = Paths.name_error(path.get_file())
	if error.is_empty():
		error = Shared.target_error(path, request.get("expected_parent"))
	if not error.is_empty():
		return Values.failure(error)
	var template: Variant = request.get("template")
	var name: Variant = request.get("node_name")
	if not template is String or not name is String or not String(name).is_valid_identifier():
		return Values.failure("Choose a scene template and a valid root node identifier.")
	var root := ROOTS.filter(func(candidate: String) -> bool: return path.begins_with(candidate + "/"))[0] as String
	if (root == ROOTS[0] and template not in ["map_2d", "empty_2d", "empty_3d"]) or (root == ROOTS[1] and template != "presentation") or (root == ROOTS[2] and template not in ["control", "hud"]):
		return Values.failure("That template is unavailable in the selected scene library.")
	var made := Templates.create(template, name, request.get("root_type", "Node2D"))
	if not made["ok"]:
		return made
	var folder := "res://.godot/authoring/scene_draft_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if DirAccess.dir_exists_absolute(folder) or DirAccess.make_dir_recursive_absolute(folder) != OK:
		return Values.failure("Could not create a unique scene staging directory.")
	var stage := folder.path_join("draft.tscn")
	var uid := ResourceUID.create_id()
	if ResourceSaver.save(made["value"], stage) != OK or ResourceSaver.set_uid(stage, uid) != OK:
		return _discard(stage, Values.failure("Could not save and identify the scene draft."))
	var text := Files.format(FileAccess.get_file_as_string(stage), true)
	var graph := Graph.read(stage)
	if not graph["ok"] or graph["value"]["nodes"]["."]["name"] != name or Files.resource_uid(stage) != uid:
		return _discard(stage, Values.failure("The scene draft failed hierarchy or UID verification."))
	error = Shared.target_error(path, request.get("expected_parent"))
	return _discard(stage, Values.failure(error) if not error.is_empty() else Values.success({"source_path": path, "source_text": text, "content_hash": text.sha256_text(), "uid": ResourceUID.id_to_text(uid), "node_name": name, "root_type": graph["value"]["nodes"]["."]["type"], "dependency_hashes": graph["value"]["dependency_hashes"]}))


static func _discard(stage: String, result: Dictionary) -> Dictionary:
	if FileAccess.file_exists(stage) and DirAccess.remove_absolute(stage) != OK:
		return Values.failure("Could not remove the scene staging file.")
	if DirAccess.remove_absolute(stage.get_base_dir()) != OK:
		return Values.failure("Could not remove the scene staging directory.")
	if result["ok"]:
		result["value"]["dependency_hashes"].erase(stage)
	return result


static func deletion_preview(path: String, request: Dictionary) -> Dictionary:
	var checked := check_scene(path)
	if not checked["ok"]:
		return checked
	return Shared.deletion_preview(path, request.get("expected_hash"), check_scene)
