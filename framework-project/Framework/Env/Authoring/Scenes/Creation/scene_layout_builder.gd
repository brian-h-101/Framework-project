extends RefCounted

const Preset = preload("res://Framework/Env/Configuration/Resources/Presentation/scene_layout_preset.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Properties = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_properties.gd")
const Scripts = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_script.gd")

const PRESET_FOLDER := "res://Framework/Content/Gameplay/Presets"
const SCENE_FOLDER := "res://Framework/Content/Gameplay/Presentation/Layouts"
const SUFFIX := ".layout.tres"
const SOURCE_META := &"layout_preset_source"
const CONTENT_META := &"layout_preset_digest"


static func path_error(path: String) -> String:
	if not path.ends_with(SUFFIX) or path.get_file().begins_with("."):
		return "Choose a .layout.tres preset under Content/Gameplay/Presets."
	var error := category_error(path.get_base_dir())
	return Paths.project_error(path) if error.is_empty() else error


static func category_error(path: String) -> String:
	if path != PRESET_FOLDER:
		if not path.begins_with(PRESET_FOLDER + "/"):
			return "Choose a category under Content/Gameplay/Presets."
		for folder in path.trim_prefix(PRESET_FOLDER + "/").split("/"):
			var error := Paths.name_error(folder)
			if not error.is_empty():
				return error
	return Paths.project_error(path)


static func scene_path(preset_path: String) -> String:
	return SCENE_FOLDER.path_join(preset_path.trim_prefix(PRESET_FOLDER + "/").trim_suffix(SUFFIX) + ".tscn")


static func valid_type(native_type: String) -> bool:
	return native_type != "InstancePlaceholder" and ClassDB.class_exists(native_type) and ClassDB.can_instantiate(native_type) and ClassDB.is_parent_class(native_type, "Node") and ClassDB.class_get_api_type(native_type) == ClassDB.API_CORE


static func valid_name(name: String) -> bool:
	return not name.strip_edges().is_empty() and name not in [".", ".."] and name.validate_node_name() == name and not name.contains("\\") and not name.contains("\n") and not name.contains("\r")


static func record(name: String, native_type: String) -> Dictionary:
	return {"name": name, "type": native_type, "properties": {}, "children": []}


static func read(path: String) -> Dictionary:
	var error := path_error(path)
	if not error.is_empty():
		return Values.failure(error)
	var checked := Files.check_path(path)
	if not checked["ok"]:
		return checked
	var hashes := {}
	checked = dependency(path, hashes, 0)
	if not checked["ok"]:
		return checked
	var preset := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Preset
	if preset == null:
		return Values.failure("Expected a Layout Preset.")
	return Values.success({"preset": preset, "hashes": hashes})


static func dependency(path: String, hashes: Dictionary, depth: int) -> Dictionary:
	if hashes.has(path):
		return Values.success(true)
	var error := Paths.project_error(path)
	if not error.is_empty():
		return Values.failure(error)
	if depth > 32 or hashes.size() >= 1000 or not FileAccess.file_exists(path):
		return Values.failure("Missing or excessive layout dependencies: " + path)
	var hash := FileAccess.get_sha256(path)
	if hash.is_empty():
		return Values.failure("Could not read layout dependency: " + path)
	hashes[path] = hash
	if path.get_extension() not in ["tres", "tscn", "res", "scn", "gd"]:
		return Values.success(true)
	for reference: String in ResourceLoader.get_dependencies(path):
		var source := reference.get_slice("::", 2) if reference.contains("::") else reference
		if reference.begins_with("uid://"):
			var uid := ResourceUID.text_to_id(reference.get_slice("::", 0))
			if ResourceUID.has_id(uid) and FileAccess.file_exists(ResourceUID.get_id_path(uid)):
				source = ResourceUID.get_id_path(uid)
		if not source.begins_with("res://"):
			source = path.get_base_dir().path_join(source).simplify_path()
		var checked := dependency(source, hashes, depth + 1)
		if not checked["ok"]:
			return checked
	return Values.success(true)


static func materialize(preset: Preset, hashes: Dictionary) -> Dictionary:
	var built := _node(preset.root, {"count": 0}, 0, hashes)
	if built["ok"]:
		_set_owners(built["value"], built["value"])
	return built


static func _node(spec: Dictionary, state: Dictionary, depth: int, hashes: Dictionary) -> Dictionary:
	state["count"] += 1
	if depth > 24 or state["count"] > 256:
		return Values.failure("Layouts support up to 256 nodes and 24 levels of children.")
	if not spec.get("name") is String or not valid_name(spec["name"]) or not spec.get("type") is String or not valid_type(spec["type"]):
		return Values.failure("Each layout node needs a valid name and an instantiable Godot node type.")
	if not spec.get("properties") is Dictionary or not spec.get("children") is Array:
		return Values.failure("A layout node requires a properties dictionary and children array.")
	var node := ClassDB.instantiate(spec["type"]) as Node
	node.name = spec["name"]
	var script: Variant = spec.get("script")
	if script != null:
		if not script is Script:
			return _failure(node, "Choose a saved script for " + spec["name"] + ".")
		var checked := Scripts.inspect(script.resource_path, spec["type"])
		if not checked["ok"]:
			return _failure(node, checked["error"])
		hashes.merge(checked["value"]["dependency_hashes"])
		node.set_script(script)
		if node.get_script() != script:
			return _failure(node, "Could not attach the script to " + spec["name"] + ".")
	var entries := _property_entries(node)
	for key: Variant in spec["properties"]:
		if not key is String or not entries.has(key):
			return _failure(node, "%s has no supported property '%s'." % [spec["name"], key])
		var value: Variant = spec["properties"][key]
		var entry: Dictionary = entries[key]
		if entry["type"] != typeof(value):
			return _failure(node, "'%s' on %s requires %s." % [key, spec["name"], entry["kind"]])
		if value is Resource:
			if value is PackedScene or value is Script or value is Preset or value.resource_path.get_extension() != "tres":
				return _failure(node, "Assign a saved data .tres Resource to " + key + ".")
			var checked := dependency(value.resource_path, hashes, 0)
			if not checked["ok"]:
				return _failure(node, checked["error"])
		elif value is float and not is_finite(value):
			return _failure(node, "Property " + key + " requires a finite value.")
		if key.begins_with("metadata/"):
			if key in ["metadata/entity_definition", "metadata/entity_key", "metadata/ui_anchor_role"] and String(value).strip_edges().is_empty():
				return _failure(node, "Property " + key + " requires nonempty text.")
			node.set_meta(key.trim_prefix("metadata/"), value)
		else:
			node.set(key, value)
			var assigned: Variant = node.get(key)
			if typeof(assigned) != typeof(value) or assigned != value:
				return _failure(node, "Godot rejected the value for '%s' on %s." % [key, spec["name"]])
	var names := {}
	for child: Variant in spec["children"]:
		if not child is Dictionary or not child.get("name") is String or names.has(child["name"]):
			return _failure(node, "Children of %s must have unique names." % spec["name"])
		names[child["name"]] = true
		var built := _node(child, state, depth + 1, hashes)
		if not built["ok"]:
			return _failure(node, built["error"])
		node.add_child(built["value"])
	return Values.success(node)


static func property_options(node: Node, stored: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries := _property_entries(node)
	var names := entries.keys()
	names.sort()
	for key: String in names:
		var entry: Dictionary = entries[key]
		var value: Variant = stored.get(key)
		var text := ""
		if value is Resource:
			text = value.resource_path
		elif value != null:
			text = Properties._format(value, entry["kind"])
		elif key.begins_with("metadata/"):
			text = Properties.FRAMEWORK_METADATA[key.trim_prefix("metadata/")][2]
		elif entry["kind"] != "Resource":
			value = node.get(key)
			if typeof(value) == entry["type"]:
				text = Properties._format(value, entry["kind"])
		result.append({"name": key, "kind": entry["kind"], "value": text})
	return result


static func _property_entries(node: Node) -> Dictionary:
	var entries := {}
	for entry in node.get_property_list():
		var key: String = entry["name"]
		if key in ["name", "script"] or key.begins_with("metadata/"):
			continue
		var kind := Properties._native_type(entry)
		const REQUIRED = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR
		if entry["type"] == TYPE_OBJECT and entry["hint"] == PROPERTY_HINT_RESOURCE_TYPE and (entry["usage"] & REQUIRED) == REQUIRED and (entry["usage"] & PROPERTY_USAGE_READ_ONLY) == 0:
			kind = "Resource"
		if not kind.is_empty():
			entries[key] = {"kind": kind, "type": entry["type"]}
	for key: String in Properties.FRAMEWORK_METADATA:
		var spec: Array = Properties.FRAMEWORK_METADATA[key]
		if node.is_class(spec[1]):
			entries["metadata/" + key] = {"kind": spec[0], "type": TYPE_BOOL if spec[0] == "bool" else TYPE_STRING_NAME}
	return entries


static func _set_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owners(child, root)


static func digest(hashes: Dictionary) -> String:
	return JSON.stringify(hashes, "", true).sha256_text()


static func resolve(preset_path: String) -> Dictionary:
	var read_result := read(preset_path)
	if not read_result["ok"]:
		return read_result
	var hashes: Dictionary = read_result["value"]["hashes"]
	var built := materialize(read_result["value"]["preset"], hashes)
	if not built["ok"]:
		return built
	built["value"].free()
	var path := scene_path(preset_path)
	var error := Paths.project_error(path)
	if not error.is_empty():
		return Values.failure(error)
	if not FileAccess.file_exists(path):
		return Values.failure("Build the selected Layout Preset in Framework Resources first.")
	hashes[path] = FileAccess.get_sha256(path)
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var dependencies := hashes.duplicate()
	dependencies.erase(path)
	if _saved_marker(scene, SOURCE_META) != preset_path or _saved_marker(scene, CONTENT_META) != digest(dependencies):
		return Values.failure("Rebuild the selected Layout Preset in Framework Resources before placing it.")
	var instance := scene.instantiate()
	var matches := instance != null and _matches(instance, read_result["value"]["preset"].root)
	if instance != null:
		instance.free()
	if not matches:
		return Values.failure("The generated scene changed. Rebuild the Layout Preset before placing it.")
	var checked := verify_hashes(hashes, hashes)
	return Values.success({"scene_path": path, "dependency_hashes": hashes}) if checked["ok"] else checked


static func build(preset_path: String, expected: Dictionary) -> Dictionary:
	var loaded := read(preset_path)
	if not loaded["ok"]:
		return loaded
	var preset: Preset = loaded["value"]["preset"]
	var hashes: Dictionary = loaded["value"]["hashes"]
	var built := materialize(preset, hashes)
	if not built["ok"]:
		return built
	var node: Node = built["value"]
	var checked := verify_hashes(expected, hashes)
	if not checked["ok"]:
		node.free()
		return checked
	node.set_meta(SOURCE_META, preset_path)
	node.set_meta(CONTENT_META, digest(hashes))
	var packed := PackedScene.new()
	var packed_error := packed.pack(node)
	node.free()
	if packed_error != OK:
		return Values.failure("Could not pack layout scene: " + error_string(packed_error))
	var path := scene_path(preset_path)
	var error := Paths.project_error(path)
	if not error.is_empty():
		return Values.failure(error)
	var existing_hash := ""
	var uid := ResourceUID.create_id()
	if FileAccess.file_exists(path):
		existing_hash = FileAccess.get_sha256(path)
		var existing := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		if _saved_marker(existing, SOURCE_META) != preset_path:
			return Values.failure("The destination scene belongs to a different source: " + path)
		var old_uid := Files.resource_uid(path)
		if old_uid != ResourceUID.INVALID_ID:
			uid = old_uid
	var folder := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder) != OK:
		return Values.failure("Could not create the generated layout category: " + folder)
	var stage := folder.path_join(".layout-" + Crypto.new().generate_random_bytes(12).hex_encode() + ".tscn")
	if FileAccess.file_exists(stage):
		return Values.failure("A layout staging scene already exists.")
	if ResourceSaver.save(packed, stage) != OK or ResourceSaver.set_uid(stage, uid) != OK:
		return _discard(stage, "Could not write and identify the staged layout scene.")
	var reloaded := ResourceLoader.load(stage, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if _saved_marker(reloaded, SOURCE_META) != preset_path or _saved_marker(reloaded, CONTENT_META) != digest(hashes) or Files.resource_uid(stage) != uid:
		return _discard(stage, "Staged layout metadata or UID did not round-trip.")
	var instance := reloaded.instantiate()
	var verified := instance != null and _matches(instance, preset.root)
	if instance != null:
		instance.free()
	if not verified:
		return _discard(stage, "Staged layout nodes, scripts, or properties did not round-trip.")
	checked = verify_hashes(hashes, hashes)
	if not checked["ok"] or (FileAccess.file_exists(path) and FileAccess.get_sha256(path) != existing_hash) or (not existing_hash.is_empty() and not FileAccess.file_exists(path)):
		return _discard(stage, "The layout or destination scene changed during the build.")
	if DirAccess.rename_absolute(stage, path) != OK:
		return _discard(stage, "Could not publish the layout scene.")
	return Values.success({"scene_path": path, "uid": ResourceUID.id_to_text(uid)})


static func _matches(node: Node, spec: Dictionary) -> bool:
	if String(node.name) != spec["name"] or node.get_class() != spec["type"] or node.get_child_count() != spec["children"].size():
		return false
	var saved_script: Script = node.get_script()
	var expected_script: Script = spec.get("script")
	if (saved_script.resource_path if saved_script != null else "") != (expected_script.resource_path if expected_script != null else ""):
		return false
	for key: String in spec["properties"]:
		var value: Variant = node.get_meta(key.trim_prefix("metadata/"), null) if key.begins_with("metadata/") else node.get(key)
		if Files.canonical(value) != Files.canonical(spec["properties"][key]):
			return false
	for index in node.get_child_count():
		if not _matches(node.get_child(index), spec["children"][index]):
			return false
	return true


static func _saved_marker(scene: PackedScene, key: StringName) -> String:
	if scene == null or scene.get_state().get_node_count() == 0:
		return ""
	var state := scene.get_state()
	for index in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == StringName("metadata/" + String(key)):
			return String(state.get_node_property_value(0, index))
	return ""


static func verify_hashes(expected: Dictionary, required: Dictionary) -> Dictionary:
	for source: String in required:
		if expected.get(source) != required[source] or FileAccess.get_sha256(source) != required[source]:
			return Values.failure("Layout dependency changed or was not inspected: " + source)
	return Values.success(true)


static func _failure(node: Node, error: String) -> Dictionary:
	node.free()
	return Values.failure(error)


static func _discard(stage: String, error: String) -> Dictionary:
	if FileAccess.file_exists(stage) and DirAccess.remove_absolute(stage) != OK:
		error += " Could not remove staging file: " + stage
	return Values.failure(error)
