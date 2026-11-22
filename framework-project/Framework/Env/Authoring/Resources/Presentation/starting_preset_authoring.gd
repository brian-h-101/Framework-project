extends RefCounted

const Authored = preload("res://Framework/Env/Setup/Library/authored_library.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Preset = preload("res://Framework/Infrastructure/API/Entity/Resources/starting_attributes_resource.gd")
const Fragment = preload("res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const ValueTree = preload("res://Framework/Env/Authoring/Shared/value_tree.gd")
const Collections = preload("res://Framework/Env/Authoring/Shared/collection_editing.gd")
const Library = preload("res://Framework/Env/Authoring/Resources/Library/behavior_library.gd")

const ROOT = "res://Framework/Content/Gameplay/Presentation/"
const OVERRIDES = "Overrides"
const EFFECTIVE = "Effective Attributes"


static func supports(path: String, resource: Resource) -> bool:
	return path.begins_with(ROOT) and resource is Preset


static func graph(path: String, resource: Preset, hashes: Dictionary, browsing: bool) -> Dictionary:
	var error := Paths.project_error(path)
	if not error.is_empty():
		return Values.failure(error)
	var definition := resource.to_definition()
	if not definition.get("ok", true):
		return definition
	var fragments: Array[String] = []
	for fragment in resource.fragments:
		fragments.append(fragment.resource_path)
	var state := {"count": 0, "error": ""}
	var tree := ValueTree.build({
		"Definition ID": resource.id,
		"Fragments": fragments,
		EFFECTIVE: definition["containers"],
		OVERRIDES: resource.overrides,
	}, [], "data", true, state)
	if not state["error"].is_empty():
		return Values.failure(state["error"])
	_apply_capabilities(tree)
	var checked := Files.check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	var node := {
		"id": String(resource.id), "kind": "starting_attributes", "source_path": path,
		"content_hash": hashes[path], "links": [], "data": tree, "fragment_paths": fragments,
	}
	var result := {"version": 2, "roots": [path], "nodes": {path: node},
		"dependency_hashes": hashes, "catalog_paths": []}
	if browsing:
		result["mode"] = "browse"
	return Values.success(result)


static func _apply_capabilities(node: Dictionary) -> void:
	var path: Array = node["path"]
	var section: String = path[0]["text"] if not path.is_empty() else ""
	var authored := section == OVERRIDES
	var mutable := authored and path.size() > 1 and node["mutable"] as bool
	node["editable"] = node["editable"] and (
		(authored and path.size() >= 3) or (section == EFFECTIVE and path.size() == 3)
	)
	node["mutable"] = mutable
	node["can_add"] = authored and node["can_add"]
	node["can_remove"] = mutable
	node["can_rename"] = mutable and path[-1]["kind"] != "index"
	node["can_add_effect"] = false
	node["allowed_types"] = []
	node["choices"] = []
	for child: Dictionary in node["children"]:
		_apply_capabilities(child)


static func edit(path: String, request: Dictionary) -> Dictionary:
	if not path.begins_with(ROOT):
		return Values.failure("Choose a starting preset inside Framework/Content/Gameplay/Presentation.")
	var error := Paths.project_error(path)
	if not error.is_empty():
		return Values.failure(error)
	var original := {}
	var checked := Library._hash_resources(path, original, 0)
	if not checked["ok"]:
		return checked
	var expected: Variant = request.get("expected_hashes")
	if not expected is Dictionary:
		return Values.failure("An edit requires inspected preset and fragment hashes.")
	checked = Files.check_hashes(expected, original)
	if not checked["ok"]:
		return checked
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Preset
	if resource == null:
		return Values.failure("Expected a starting attributes Resource.")

	var hashes := original.duplicate()
	if request.get("operation") == "set_fragments":
		checked = _set_fragments(resource, request.get("fragment_paths"), expected, hashes)
	else:
		checked = _edit_attributes(resource, request)
	if not checked["ok"]:
		return checked
	var definition := resource.to_definition()
	if not definition.get("ok", true):
		return definition
	return Files.save(path, hashes, resource, _snapshot)


static func _set_fragments(resource: Preset, selected: Variant, expected: Dictionary, hashes: Dictionary) -> Dictionary:
	if not selected is Array or selected.size() > 1000:
		return Values.failure("Choose up to 1000 authored attribute fragments.")
	var fragments: Array[Fragment] = []
	var seen := {}
	for path: Variant in selected:
		if not path is String or seen.has(path):
			return Values.failure("Fragment selections require unique authored paths.")
		seen[path] = true
		var error := Authored.resource_error(path)
		if not error.is_empty():
			return Values.failure(error)
		var dependencies := {}
		var checked := Library._hash_resources(path, dependencies, 0)
		if not checked["ok"]:
			return checked
		checked = Files.check_hashes(expected, {path: dependencies[path]})
		if not checked["ok"]:
			return checked
		var fragment := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Fragment
		if fragment == null:
			return Values.failure("Expected an authored container fragment: " + path)
		fragments.append(fragment)
		hashes.merge(dependencies)
	resource.fragments = fragments
	return Values.success(true)


static func _edit_attributes(resource: Preset, request: Dictionary) -> Dictionary:
	var path: Variant = request.get("path")
	if not path is Array or path.is_empty() or not path[0] is Dictionary or path[0].get("kind") != "String":
		return Values.failure("Choose an attribute or override entry.")
	var change := request.duplicate()
	var route: Array = path.slice(1)
	change["path"] = route
	if path[0].get("text") == OVERRIDES:
		return Collections.apply(resource.overrides, change)
	if path[0].get("text") != EFFECTIVE or route.size() != 2 or request.get("operation") != "set":
		return Values.failure("Only scalar attributes and authored overrides can be edited here.")
	var definition := resource.to_definition()
	if not definition.get("ok", true):
		return definition
	var effective: Dictionary = definition["containers"]
	var checked := Collections.apply(effective, change)
	if not checked["ok"]:
		return checked
	var container_id := StringName(route[0]["text"])
	var container: Dictionary = effective[container_id]
	var key := Values.key_for(container, route[1])
	if not key["ok"]:
		return key
	if not resource.overrides.has(container_id):
		resource.overrides[container_id] = {}
	var overrides: Dictionary = resource.overrides[container_id]
	overrides[key["value"]] = container[key["value"]]
	return Values.success(true)


static func _snapshot(resource: Resource) -> Dictionary:
	if not resource is Preset:
		return {}
	var metadata := {}
	for key in resource.get_meta_list():
		metadata[key] = resource.get_meta(key)
	return {"script": resource.get_script().resource_path, "id": resource.id,
		"fragments": resource.fragments, "overrides": resource.overrides,
		"resource_name": resource.resource_name, "resource_local_to_scene": resource.resource_local_to_scene,
		"metadata": metadata}
