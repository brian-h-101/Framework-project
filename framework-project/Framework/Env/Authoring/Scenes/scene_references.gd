extends RefCounted

const Document = preload("res://Framework/Env/Authoring/Scenes/scene_document.gd")


static func rewrite(document: Dictionary, graph: Dictionary, old_path: String, new_path: String, removing: bool) -> Dictionary:
	var edits: Array[Dictionary] = []
	# Borrowed nodes may refer outside their instance. A single-file edit cannot
	# silently change their shared source scene to repair such a reference.
	for owner: String in graph["nodes"]:
		if removing and inside(owner, old_path):
			continue
		for reference: Dictionary in graph["nodes"][owner]["references"].values():
			if reference["source_path"] == graph["source_path"]:
				continue
			for raw: String in reference["paths"]:
				var transformed := transform(raw, owner, old_path, new_path, removing)
				if not transformed["ok"] or transformed["value"] != raw:
					return Document.failure("A reference owned by %s cannot be repaired locally: %s (%s)." % [reference["source_path"], owner, raw])
	for section: Dictionary in document["sections"]:
		var tag: String = section["tag"]
		var owner := Document.node_path(section) if tag == "node" else ""
		if removing and tag == "node" and inside(owner, old_path):
			continue
		if tag == "connection":
			var from := Document.attribute(section, "from")
			var to := Document.attribute(section, "to")
			if removing and (inside(from, old_path) or inside(to, old_path)):
				edits.append({"start": section["start"], "end": section["end"], "text": ""})
				continue
		for name: String in section["attributes"]:
			var field: Dictionary = section["attributes"][name]
			var is_path: bool = (tag == "node" and name in ["parent", "owner"]) or (tag == "connection" and name in ["from", "to"]) or (tag == "editable" and name == "path")
			if is_path:
				var previous: String = field["text"]
				if removing and tag == "editable" and inside(previous, old_path):
					edits.append({"start": section["start"], "end": section["end"], "text": ""})
					break
				var mapped := mapped_path(previous, old_path, new_path)
				if mapped != previous:
					edits.append(Document.replacement(field, JSON.stringify(mapped)))
			if not Document.node_paths(field["tokens"]).is_empty():
				return Document.failure("NodePath values in section headers require editing in Godot.")
		for property: Dictionary in section["properties"]:
			for token: Dictionary in Document.node_paths(property["tokens"]):
				if tag != "node":
					return Document.failure("Resource-owned NodePath values, including animation tracks, require editing in Godot: %s." % property["name"])
				var transformed := transform(token["text"], owner, old_path, new_path, removing)
				if not transformed["ok"]:
					return transformed
				if transformed["value"] != token["text"]:
					edits.append(Document.replacement(token, JSON.stringify(transformed["value"])))
	var resource_hashes := {}
	var seen := {}
	for dependency: String in graph["dependency_hashes"]:
		var guarded := _guard_resources(dependency, seen, resource_hashes)
		if not guarded["ok"]:
			return guarded
	return Document.success({"edits": edits, "resource_hashes": resource_hashes})


static func transform(raw: String, owner: String, old_path: String, new_path: String, removing: bool) -> Dictionary:
	if raw.is_empty() or raw.begins_with(":"):
		return Document.success(raw)
	var path := NodePath(raw)
	if path.is_absolute() or raw.contains("%"):
		return Document.failure("Absolute and unique-name NodePath references require editing in Godot: %s." % raw)
	var target := PackedStringArray() if owner == "." else owner.split("/")
	for index in path.get_name_count():
		var part := String(path.get_name(index))
		if part == ".":
			continue
		if part == "..":
			if target.is_empty():
				return Document.failure("NodePath leaves the selected scene boundary: %s." % raw)
			target.resize(target.size() - 1)
		else:
			target.append(part)
	var target_path := "/".join(target) if not target.is_empty() else "."
	if removing and inside(target_path, old_path):
		return Document.failure("A surviving node references the removed subtree: %s -> %s." % [owner, raw])
	var next_owner := mapped_path(owner, old_path, new_path)
	var next_target := mapped_path(target_path, old_path, new_path)
	if next_owner == owner and next_target == target_path:
		return Document.success(raw)
	var relative := _relative(next_owner, next_target)
	var colon := raw.find(":")
	return Document.success(relative + (raw.substr(colon) if colon >= 0 else ""))


static func inside(path: String, root: String) -> bool:
	return path == root or path.begins_with(root + "/")


static func mapped_path(path: String, old_path: String, new_path: String) -> String:
	return new_path + path.trim_prefix(old_path) if inside(path, old_path) else path


static func _relative(owner: String, target: String) -> String:
	var from := PackedStringArray() if owner == "." else owner.split("/")
	var to := PackedStringArray() if target == "." else target.split("/")
	var common := 0
	while common < mini(from.size(), to.size()) and from[common] == to[common]:
		common += 1
	var parts := PackedStringArray()
	for index in range(common, from.size()):
		parts.append("..")
	for index in range(common, to.size()):
		parts.append(to[index])
	return "/".join(parts) if not parts.is_empty() else "."


static func _guard_resources(scene_or_resource: String, seen: Dictionary, hashes: Dictionary) -> Dictionary:
	if seen.has(scene_or_resource):
		return Document.success(true)
	if seen.size() > 1000:
		return Document.failure("Resource reference inspection exceeds 1000 files.")
	seen[scene_or_resource] = true
	var text := FileAccess.get_file_as_string(scene_or_resource)
	var parsed := Document.parse(text)
	if not parsed["ok"]:
		return parsed
	for section: Dictionary in parsed["value"]["sections"]:
		if section["tag"] == "sub_resource":
			for property: Dictionary in section["properties"]:
				if not Document.node_paths(property["tokens"]).is_empty():
					return Document.failure("Resource-owned NodePath values, including animation tracks, require editing in Godot: %s." % scene_or_resource)
		if scene_or_resource.ends_with(".tres"):
			for property: Dictionary in section["properties"]:
				if not Document.node_paths(property["tokens"]).is_empty():
					return Document.failure("External Resource NodePaths require editing in Godot: %s." % scene_or_resource)
		if section["tag"] == "ext_resource":
			var dependency := Document.attribute(section, "path")
			if dependency.get_extension() == "tres":
				if not dependency.begins_with("res://"):
					dependency = scene_or_resource.get_base_dir().path_join(dependency).simplify_path()
				if not dependency.begins_with("res://") or not FileAccess.file_exists(dependency):
					return Document.failure("Cannot inspect an external Resource dependency: %s." % dependency)
				if dependency.simplify_path() != dependency or dependency.contains("\\"):
					return Document.failure("Invalid external Resource dependency: %s." % dependency)
				var directory := DirAccess.open("res://")
				var current := "res://"
				for part in dependency.trim_prefix("res://").split("/"):
					current = current.path_join(part)
					if part in ["", ".", ".."] or part.contains(":") or directory == null or directory.is_link(current):
						return Document.failure("External Resource paths cannot use links or leave the project.")
				hashes[dependency] = FileAccess.get_sha256(dependency)
				var guarded := _guard_resources(dependency, seen, hashes)
				if not guarded["ok"]:
					return guarded
	return Document.success(true)
