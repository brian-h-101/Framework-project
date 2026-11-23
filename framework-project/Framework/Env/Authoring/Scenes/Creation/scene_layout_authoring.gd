extends RefCounted

const Builder = preload("res://Framework/Env/Authoring/Scenes/Creation/scene_layout_builder.gd")
const Preset = Builder.Preset
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Drafts = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const ValueTree = preload("res://Framework/Env/Authoring/Shared/value_tree.gd")


static func create(path: String, request: Dictionary) -> Dictionary:
	var error := Builder.path_error(path)
	if error.is_empty():
		error = Paths.name_error(path.get_file())
	if not error.is_empty():
		return Values.failure(error)
	var name: Variant = request.get("name")
	var native_type: Variant = request.get("node_type")
	if not name is String or not Builder.valid_name(name) or not native_type is String or not Builder.valid_type(native_type):
		return Values.failure("Choose a valid root node name and native type.")
	var folder := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder):
		if folder != Builder.PRESET_FOLDER or request.get("expected_parent", "") != "":
			return Values.failure("The selected preset category no longer exists.")
		if DirAccess.make_dir_absolute(folder) != OK:
			return Values.failure("Could not create the Presets directory.")
		request["expected_parent"] = Drafts.fingerprint(folder)
	var preset := Preset.new()
	preset.root = Builder.record(name, native_type)
	var expected: Variant = request.get("expected_parent", Drafts.fingerprint(folder))
	var draft := Drafts.draft(path, expected, preset, _snapshot)
	if draft["ok"]:
		draft["value"]["expected_parent"] = expected
	return draft


static func categories() -> Dictionary:
	var error := Builder.category_error(Builder.PRESET_FOLDER)
	if not error.is_empty():
		return Values.failure(error)
	if not DirAccess.dir_exists_absolute(Builder.PRESET_FOLDER):
		return Values.success([{"source_path": Builder.PRESET_FOLDER, "fingerprint": ""}])
	var folders: Array[Dictionary] = []
	var result := _categories(Builder.PRESET_FOLDER, folders, 0)
	return Values.success(folders) if result["ok"] else result


static func _categories(path: String, folders: Array[Dictionary], depth: int) -> Dictionary:
	if depth > 64 or folders.size() >= 10000:
		return Values.failure("The preset category catalogue exceeds its folder or depth limit.")
	var directory := DirAccess.open(path)
	if directory == null:
		return Values.failure("Could not inspect preset category: " + path)
	folders.append({"source_path": path, "fingerprint": Drafts.fingerprint(path)})
	for name in directory.get_directories():
		var child := path.path_join(name)
		if not Builder.category_error(child).is_empty():
			continue
		var listed := _categories(child, folders, depth + 1)
		if not listed["ok"]:
			return listed
	return Values.success(true)


static func create_category(path: String, request: Dictionary) -> Dictionary:
	var error := Builder.category_error(path)
	if not error.is_empty() or path == Builder.PRESET_FOLDER:
		return Values.failure(error if not error.is_empty() else "Choose a subcategory under Presets.")
	var parent := path.get_base_dir()
	var expected: Variant = request.get("expected_parent")
	if parent == Builder.PRESET_FOLDER and expected == "" and not DirAccess.dir_exists_absolute(parent):
		if DirAccess.make_dir_absolute(parent) != OK:
			return Values.failure("Could not create the Presets directory.")
		expected = Drafts.fingerprint(parent)
	error = Drafts.target_error(path, expected)
	if not error.is_empty():
		return Values.failure(error)
	if DirAccess.make_dir_absolute(path) != OK:
		return Values.failure("Could not create the preset category: " + path)
	return Values.success({"source_path": path})


static func preview_category_deletion(path: String, request: Dictionary) -> Dictionary:
	var error := Builder.category_error(path)
	if not error.is_empty() or path == Builder.PRESET_FOLDER:
		return Values.failure(error if not error.is_empty() else "Choose a subcategory under Presets.")
	return Drafts.folder_deletion_preview(path, request.get("expected_directory"))


static func inspect(path: String, node_path: String) -> Dictionary:
	var loaded := Builder.read(path)
	if not loaded["ok"]:
		return loaded
	var preset: Preset = loaded["value"]["preset"]
	var hashes: Dictionary = loaded["value"]["hashes"]
	var built := Builder.materialize(preset, hashes)
	if not built["ok"]:
		return built
	var root: Node = built["value"]
	var entry := _record_at(preset.root, node_path)
	var node := root if node_path == "." else root.get_node_or_null(NodePath(node_path))
	var result := Values.failure("Choose a current layout node.")
	if not entry.is_empty() and node != null:
		result = Values.success({"name": entry["name"], "type": entry["type"], "dependency_hashes": hashes,
			"properties": Builder.property_options(node, entry["properties"])})
	root.free()
	var checked := Builder.verify_hashes(hashes, hashes)
	return result if checked["ok"] else checked


static func edit(path: String, request: Dictionary) -> Dictionary:
	var expected: Variant = request.get("expected_hashes")
	var node_path: Variant = request.get("node_path")
	if not expected is Dictionary or not node_path is String:
		return Values.failure("Inspect the layout and select a node before editing.")
	var loaded := Builder.read(path)
	if not loaded["ok"]:
		return loaded
	var preset: Preset = loaded["value"]["preset"]
	var hashes: Dictionary = loaded["value"]["hashes"]
	var previous := Builder.materialize(preset, hashes)
	if not previous["ok"]:
		return previous
	previous["value"].free()
	var verified := Builder.verify_hashes(expected, hashes)
	if not verified["ok"]:
		return verified
	var entry := _record_at(preset.root, node_path)
	if entry.is_empty():
		return Values.failure("The layout node no longer exists.")
	if request.get("operation") in ["attach_script", "assign_resource"]:
		var asset: Variant = request.get("asset_path")
		if not asset is String:
			return Values.failure("Choose a saved project script or data Resource.")
		var collected := Builder.dependency(asset, hashes, 0)
		if not collected["ok"]:
			return collected
		verified = Builder.verify_hashes(expected, {asset: hashes[asset]})
		if not verified["ok"]:
			return verified
	var updated := _change(preset, entry, node_path, request)
	if not updated["ok"]:
		return updated
	var built := Builder.materialize(preset, hashes)
	if not built["ok"]:
		return built
	built["value"].free()
	return Files.save(path, {path: hashes[path]}, preset, _snapshot, Builder.verify_hashes.bind(hashes, hashes))


static func _change(preset: Preset, entry: Dictionary, node_path: String, request: Dictionary) -> Dictionary:
	match request.get("operation"):
		"add", "rename":
			var name: Variant = request.get("name")
			if not name is String or not Builder.valid_name(name):
				return Values.failure("Choose a valid Godot node name.")
			if request["operation"] == "rename":
				entry["name"] = name
			else:
				var type: Variant = request.get("node_type")
				if not type is String or not Builder.valid_type(type):
					return Values.failure("Choose an instantiable native Node type.")
				entry["children"].append(Builder.record(name, type))
		"remove":
			if node_path == ".":
				return Values.failure("The layout root cannot be removed.")
			var parent := _record_at(preset.root, node_path.get_base_dir())
			parent["children"].erase(entry)
		"attach_script":
			var script_path: Variant = request.get("asset_path")
			var checked := _asset(script_path, "gd")
			if not checked["ok"]:
				return checked
			entry["script"] = checked["value"]
		"set_property", "assign_resource":
			var key: Variant = request.get("property_name")
			if not key is String or key.is_empty():
				return Values.failure("Choose a layout node property.")
			var assigned: Dictionary
			if request["operation"] == "assign_resource":
				assigned = _asset(request.get("asset_path"), "tres")
			else:
				var kind: Variant = request.get("property_type")
				var text: Variant = request.get("property_value")
				if not kind is String or not text is String or text.length() > 65536:
					return Values.failure("Provide a typed property value of up to 65536 characters.")
				assigned = Builder.Properties._parse_value(kind, text)
			if not assigned["ok"]:
				return assigned
			entry["properties"][key] = assigned["value"]
		_:
			return Values.failure("Choose a Layout Preset editing operation.")
	return Values.success(true)


static func _asset(path: Variant, extension: String) -> Dictionary:
	if not path is String or path.get_extension() != extension or not Paths.project_error(path).is_empty() or not FileAccess.file_exists(path):
		return Values.failure("Choose a saved project ." + extension + " file.")
	var asset := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if asset == null:
		return Values.failure("Could not load " + path + ".")
	return Values.success(asset)


static func _record_at(root: Dictionary, path: String) -> Dictionary:
	if path in [".", ""]:
		return root
	var entry := root
	for segment in path.split("/"):
		var child := {}
		for item: Dictionary in entry["children"]:
			if item["name"] == segment:
				child = item
				break
		if child.is_empty():
			return {}
		entry = child
	return entry


static func graph(path: String, preset: Preset, hashes: Dictionary, browsing: bool) -> Dictionary:
	var checked := Builder.materialize(preset, {})
	if not checked["ok"]:
		return checked
	checked["value"].free()
	var state := {"count": 0, "error": ""}
	var data := ValueTree.build({"Root": _describe(preset.root), "Generated Scene": Builder.scene_path(path)}, [], "data", false, state)
	if not state["error"].is_empty():
		return Values.failure(state["error"])
	_mark(data["children"][0], ".")
	_complete(data)
	checked = Files.check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	var node := {"kind": "layout", "id": preset.root["name"], "source_path": path, "content_hash": hashes[path], "links": [], "data": data}
	var result := {"version": 2, "roots": [path], "nodes": {path: node}, "dependency_hashes": hashes, "catalog_paths": []}
	if browsing:
		result["mode"] = "browse"
	return Values.success(result)


static func _describe(entry: Dictionary) -> Dictionary:
	var properties := {}
	for key: String in entry["properties"]:
		var value: Variant = entry["properties"][key]
		properties[key] = value.resource_path if value is Resource else value
	var children := {}
	for child: Dictionary in entry["children"]:
		children[child["name"]] = _describe(child)
	var script: Script = entry.get("script")
	return {"Name": entry["name"], "Type": entry["type"], "Script": script.resource_path if script != null else "",
		"Properties": properties, "Children": children}


static func _mark(row: Dictionary, path: String) -> void:
	row["layout_path"] = path
	for field: Dictionary in row["children"]:
		if field["label"] == "Children":
			for child: Dictionary in field["children"]:
				_mark(child, child["label"] if path == "." else path.path_join(child["label"]))


static func _complete(row: Dictionary) -> void:
	row.merge({"can_rename": false, "can_remove": false, "can_add_effect": false, "allowed_types": [], "choices": []})
	for child: Dictionary in row["children"]:
		_complete(child)


static func _snapshot(resource: Preset) -> Dictionary:
	return {"script": resource.get_script(), "root": resource.root}
