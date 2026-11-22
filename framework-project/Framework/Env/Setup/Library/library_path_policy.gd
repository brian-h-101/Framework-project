extends RefCounted


static func project_error(path: String) -> String:
	if not path.begins_with("res://") or path.simplify_path() != path or path.contains("\\") or path.contains("::"):
		return "Libraries require canonical project paths."
	if path == "res://":
		return ""
	var directory := DirAccess.open("res://")
	if directory == null:
		return "The Godot project is unreadable."
	var current := "res://"
	for part in path.trim_prefix("res://").split("/"):
		if part.is_empty() or part in [".", ".."] or part.contains(":") or part.to_utf8_buffer().has(0):
			return "Invalid library path."
		current = current.path_join(part)
		if directory.is_link(current):
			return "Libraries do not follow symbolic links or junctions."
		if FileAccess.file_exists(current.path_join("project.godot")):
			return "Libraries cannot cross into another Godot project."
	return ""


static func path_error(path: String, root: String, allow_root: bool = true) -> String:
	if (path != root or not allow_root) and not path.begins_with(root + "/"):
		return "Choose a path inside " + root.trim_prefix("res://") + "."
	return project_error(path)


static func paths_in(
	folder: String,
	extension: String = "tres"
) -> Dictionary:
	var error := project_error(folder)
	if not error.is_empty():
		return {"ok": false, "value": null, "error": error}

	var paths := PackedStringArray()
	error = _walk(folder, paths, {}, 0, extension)
	paths.sort()

	return {
		"ok": error.is_empty(),
		"value": paths if error.is_empty() else null,
		"error": error,
	}


static func _walk(
	folder: String,
	paths: PackedStringArray,
	visited: Dictionary,
	depth: int,
	extension: String
) -> String:
	if depth > 64 or visited.size() >= 1000 or paths.size() > 10000:
		return "Resource discovery exceeds its directory, depth or file limits."

	if visited.has(folder):
		return ""

	visited[folder] = true

	var directory := DirAccess.open(folder)
	if directory == null:
		return "Resource folder does not exist: " + folder

	var entries := ResourceLoader.list_directory(folder)
	entries.sort()

	for entry in entries:
		if entry.begins_with("."):
			continue

		var path := folder.path_join(entry.trim_suffix("/"))

		if directory.is_link(entry.trim_suffix("/")):
			return "Resource discovery does not follow symbolic links or junctions: " + path

		if entry.ends_with("/"):
			if FileAccess.file_exists(path.path_join("project.godot")):
				continue

			var error := _walk(
				path, paths, visited, depth + 1, extension
			)
			if not error.is_empty():
				return error
		elif entry.get_extension() == extension:
			paths.append(path)

	return ""


static func name_error(name: String) -> String:
	if name.is_empty() or name.length() > 120 or name.begins_with(".") or name.ends_with(".") or name.ends_with(" "):
		return "Use 1–120 characters without a leading dot or trailing dots/spaces."
	for character in name:
		if character in '<>:"/\\|?*' or character.unicode_at(0) < 32:
			return "Names cannot contain Windows path separators or reserved characters."
	var stem := name.get_slice(".", 0).to_upper()
	if stem in ["CON", "PRN", "AUX", "NUL"] or (stem.length() == 4 and stem.left(3) in ["COM", "LPT"] and stem.right(1) in "123456789¹²³"):
		return "That name is reserved by Windows."
	return ""
