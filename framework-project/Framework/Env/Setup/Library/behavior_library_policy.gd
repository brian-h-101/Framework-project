extends RefCounted

const ROOT = "res://Framework/Content/Gameplay/Profiles"
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")


static func path_error(path: String, allow_root: bool = true) -> String:
	if not path.begins_with(ROOT + "/"):
		return "Choose a path under Content/Gameplay/Profiles/<category>/Behavior."
	var parts := path.trim_prefix(ROOT + "/").split("/")
	if parts.size() < (2 if allow_root else 3) or parts[1] != "Behavior":
		return "Choose a path under Content/Gameplay/Profiles/<category>/Behavior."
	return Paths.project_error(path)


static func folders() -> Dictionary:
	var error := Paths.project_error(ROOT)
	if not error.is_empty() or not DirAccess.dir_exists_absolute(ROOT):
		return {"ok": false, "value": null, "error": error if not error.is_empty() else "The Profiles folder does not exist."}
	var found := PackedStringArray()
	for entry: String in ResourceLoader.list_directory(ROOT):
		if not entry.ends_with("/") or entry.begins_with("."):
			continue
		var folder := ROOT.path_join(entry.trim_suffix("/")).path_join("Behavior")
		if not DirAccess.dir_exists_absolute(folder):
			continue
		error = path_error(folder)
		if not error.is_empty():
			return {"ok": false, "value": null, "error": error}
		found.append(folder)
	found.sort()
	return {"ok": true, "value": found, "error": ""}


static func resource_paths() -> Dictionary:
	var listed := folders()
	if not listed["ok"]:
		return listed
	var found := PackedStringArray()
	for folder: String in listed["value"]:
		var entries := Paths.paths_in(folder)
		if not entries["ok"]:
			return entries
		found.append_array(entries["value"])
	found.sort()
	return {"ok": true, "value": found, "error": ""}


static func resource_error(path: String) -> String:
	var error := path_error(path, false)
	return error if not error.is_empty() else "" if path.get_extension() == "tres" else "Choose an external .tres behavior Resource."


static func is_shared_folder(folder: String) -> bool:
	return folder.get_file() == "Shared" and folder.get_base_dir().get_base_dir() == ROOT


static func shared_folder_error(folder: String) -> String:
	if not is_shared_folder(folder):
		return "Choose a Shared folder directly under a profile in Content/Gameplay/Profiles."
	var error := Paths.project_error(folder)
	if not error.is_empty():
		return error
	var behavior_folder := folder.get_base_dir().path_join("Behavior")
	error = path_error(behavior_folder)
	if not error.is_empty():
		return error
	if not DirAccess.dir_exists_absolute(folder) or not DirAccess.dir_exists_absolute(behavior_folder):
		return "Choose an existing profile with Behavior and Shared folders."
	return ""


static func name_error(name: String) -> String:
	return Paths.name_error(name)
