extends RefCounted
const AutomationResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/automation_resource.gd")

const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd"
)
const MovementConfiguration = preload(
	"res://Framework/Env/Configuration/Resources/movement_resource.gd"
)

const MOVEMENT_SCRIPT := "res://Framework/Content/God/Movement/movement_2d.gd"

const MAX_DEPTH := 64
const MAX_NODES := 10000


static func read(scene_path: String) -> Dictionary:
	if not _is_scene_path(scene_path):
		return _failure("Expected a project-relative .tscn path: %s" % scene_path)
	if not FileAccess.file_exists(scene_path):
		return _failure("Scene file does not exist: %s" % scene_path)
	var hashes := {}
	var hashed := _hash_scenes(scene_path, [], hashes)
	if not hashed["ok"]:
		return hashed

	var packed := ResourceLoader.load(
		scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP
	) as PackedScene
	if packed == null:
		return _failure("Could not load scene: %s" % scene_path)

	var dependencies: Array[String] = []
	var composed := _compose(packed.get_state(), scene_path, [scene_path], dependencies)
	if not composed["ok"]:
		return composed
	var records: Dictionary = composed["value"]
	if not records.has("."):
		return _failure("Scene has no root node: %s" % scene_path)

	for node_path: String in records:
		var record: Dictionary = records[node_path]
		record["children"] = []
		var local: bool = record["structural_scene"] == scene_path
		record["can_add"] = (node_path == "." or local) and record["type"] != "InstancePlaceholder"
		record["can_rename"] = local and node_path != "."
		record["can_remove"] = local and node_path != "."
		record["can_attach_script"] = local and record["type"] != "InstancePlaceholder" and not record["has_script"]
		record["can_remove_script"] = local and record["has_script"] and record["script_source_path"] == scene_path
		record["can_assign_movement"] = (
			local
			and record["type"] == "CharacterBody2D"
			and record["script_path"] == MOVEMENT_SCRIPT
		)
		for property: String in ["source_path", "instance_path", "base_scene_path"]:
			var dependency: String = record[property]
			if not dependency.is_empty() and not dependencies.has(dependency):
				dependencies.append(dependency)

	for node_path: String in records:
		if node_path == ".":
			continue
		var parent_path := node_path.get_base_dir()
		if parent_path.is_empty():
			parent_path = "."
		if not records.has(parent_path):
			return _failure("Missing parent of scene node: %s" % node_path)
		records[parent_path]["children"].append(node_path)

	# An explicit sibling index can insert a local node among inherited children.
	for node_path: String in records:
		var record: Dictionary = records[node_path]
		var sibling_index: int = record["sibling_index"]
		record.erase("sibling_index")
		if node_path == "." or sibling_index < 0:
			continue
		var parent_path := node_path.get_base_dir()
		if parent_path.is_empty():
			parent_path = "."
		var siblings: Array = records[parent_path]["children"]
		siblings.erase(node_path)
		siblings.insert(mini(sibling_index, siblings.size()), node_path)

	dependencies.sort()
	for dependency in dependencies:
		if not hashes.has(dependency) or FileAccess.get_sha256(dependency) != hashes[dependency]:
			return _failure("Scene dependency changed while reading: %s" % dependency)
	return _success({
		"version": 2,
		"source_path": scene_path,
		"root": ".",
		"nodes": records,
		"dependencies": dependencies,
		"dependency_hashes": hashes,
	})


static func _compose(
	state: SceneState,
	source_path: String,
	ancestry: Array,
	dependencies: Array[String]
) -> Dictionary:
	if ancestry.size() > MAX_DEPTH:
		return _failure("Scene nesting exceeds %s levels." % MAX_DEPTH)
	if not dependencies.has(source_path):
		dependencies.append(source_path)
	var records: Dictionary = {}
	var base := state.get_base_scene_state()
	if base != null:
		var base_path: String = base.get_path()
		if not _is_scene_path(base_path) or ancestry.has(base_path):
			return _failure("Invalid or cyclic inherited scene: %s" % base_path)
		var base_result := _compose(base, base_path, ancestry + [base_path], dependencies)
		if not base_result["ok"]:
			return base_result
		records = base_result["value"]
		if records.has("."):
			records["."]["base_scene_path"] = base_path

	for index in state.get_node_count():
		var node_path := String(state.get_node_path(index)).trim_prefix("./")
		var instance := state.get_node_instance(index)
		# Inherited roots are already represented by the base SceneState above.
		if instance != null and not (node_path == "." and base != null):
			var instance_path := instance.resource_path
			if not _is_scene_path(instance_path) or ancestry.has(instance_path):
				return _failure("Invalid or cyclic scene instance: %s" % instance_path)
			var nested := _compose(
				instance.get_state(), instance_path, ancestry + [instance_path], dependencies
			)
			if not nested["ok"]:
				return nested
			var nested_records: Dictionary = nested["value"]
			for nested_path: String in nested_records:
				var placed_path: String = node_path
				if nested_path != ".":
					placed_path = nested_path if node_path == "." else node_path.path_join(nested_path)
				var placed: Dictionary = nested_records[nested_path].duplicate(true)
				placed["path"] = placed_path
				placed["instance_boundary"] = node_path
				records[placed_path] = placed
			if records.has(node_path):
				records[node_path]["instance_path"] = instance_path
				records[node_path]["structural_scene"] = source_path
				records[node_path]["structural_node_path"] = node_path

		if not records.has(node_path):
			records[node_path] = {
				"path": node_path,
				"name": "",
				"type": "",
				"source_path": source_path,
				"source_node_path": node_path,
				"instance_path": "",
				"base_scene_path": "",
				"script_path": "",
				"has_script": false,
				"script_source_path": "",
				"sibling_index": -1,
				"structural_scene": source_path,
				"structural_node_path": node_path,
				"instance_boundary": "",
				"references": {},
				"is_entity": false,
				"interaction_resource_path": "",
				"interaction_id": "",
				"automation_resource_path": "",
				"automation_id": "",
				"movement_configuration_path": "",
			}
		var record: Dictionary = records[node_path]
		record["name"] = String(state.get_node_name(index))
		record["source_path"] = source_path
		record["source_node_path"] = node_path
		var node_type := String(state.get_node_type(index))
		if not node_type.is_empty():
			record["type"] = node_type
		var sibling_index := state.get_node_index(index)
		if sibling_index >= 0:
			record["sibling_index"] = sibling_index
		if state.is_node_instance_placeholder(index):
			record["type"] = "InstancePlaceholder"
			record["instance_path"] = state.get_node_instance_placeholder(index)
		for property_index in state.get_node_property_count(index):
			var property_name := String(
				state.get_node_property_name(index, property_index)
			)
			var property_value: Variant = state.get_node_property_value(
				index, property_index
			)

			var paths: Array[String] = []
			_collect_paths(property_value, paths, 0)

			record["references"].erase(property_name)
			if not paths.is_empty():
				record["references"][property_name] = {
					"source_path": source_path,
					"paths": paths,
				}

			if property_name == "script":
				var script := property_value as Script
				record["has_script"] = script != null
				record["script_source_path"] = source_path
				var script_path: String = (
					"" if script == null else script.resource_path
				)

				# Built-in scripts have no separate file to open.
				record["script_path"] = (
					"" if script_path.contains("::") else script_path
				)

			if property_name in [
				"metadata/entity_key",
				"metadata/entity_definition",
			]:
				record["is_entity"] = true

			if property_name == "content":
				record["interaction_resource_path"] = ""
				record["interaction_id"] = ""
				record["automation_resource_path"] = ""
				record["automation_id"] = ""
				record["movement_configuration_path"] = ""

				if property_value is InteractionResource:
					var interaction: InteractionResource = property_value

					record["interaction_resource_path"] = (
						interaction.resource_path
					)
					record["interaction_id"] = String(interaction.id)

				if property_value is AutomationResource:
					record["automation_resource_path"] = property_value.resource_path
					record["automation_id"] = String(property_value.id)

				if property_value is MovementConfiguration:
					var movement: MovementConfiguration = property_value

					record["movement_configuration_path"] = (
						movement.resource_path
					)
		if records.size() > MAX_NODES:
			return _failure("Scene hierarchy exceeds %s nodes." % MAX_NODES)

	return _success(records)


static func _hash_scenes(path: String, ancestry: Array, hashes: Dictionary) -> Dictionary:
	if ancestry.has(path) or ancestry.size() > MAX_DEPTH:
		return _failure("Invalid or cyclic scene dependency: %s" % path)
	if hashes.has(path):
		return _success(true)
	if not _is_scene_path(path) or not FileAccess.file_exists(path):
		return _failure("Scene dependency does not exist: %s" % path)
	hashes[path] = FileAccess.get_sha256(path)
	for dependency in ResourceLoader.get_dependencies(path):
		var fallback := dependency.get_slice("::", 2) if dependency.contains("::") else dependency
		if dependency.contains("::"):
			var uid := ResourceUID.text_to_id(dependency.get_slice("::", 0))
			if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
				var resolved := ResourceUID.get_id_path(uid)
				if FileAccess.file_exists(resolved):
					fallback = resolved
		if fallback.ends_with(".tscn"):
			var result := _hash_scenes(fallback, ancestry + [path], hashes)
			if not result["ok"]:
				return result
	return _success(true)


static func _collect_paths(value: Variant, paths: Array[String], depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	if value is NodePath:
		paths.append(String(value))
	elif value is Array:
		for element in value:
			_collect_paths(element, paths, depth + 1)
	elif value is Dictionary:
		for key in value:
			_collect_paths(key, paths, depth + 1)
			_collect_paths(value[key], paths, depth + 1)


static func _is_scene_path(path: String) -> bool:
	if not path.begins_with("res://") or not path.ends_with(".tscn"):
		return false
	for segment in path.trim_prefix("res://").split("/"):
		if segment in ["", ".", ".."] or segment.contains(":") or segment.contains("\\"):
			return false
	return true


static func _success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
