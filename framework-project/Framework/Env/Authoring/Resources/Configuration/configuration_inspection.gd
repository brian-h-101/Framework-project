extends RefCounted

const Controls = preload("res://Framework/Env/Configuration/Resources/Input/controls_resource.gd")
const Movement = preload("res://Framework/Content/Universal/Movement/based/Configuration/movement_profile.gd")
const Controller = preload("res://Framework/Content/Universal/Movement/based/Controllers/movement_controller.gd")
const ControllerAuthoring = preload("res://Framework/Env/Authoring/Resources/Configuration/movement_controller_authoring.gd")
const Custom = preload("res://Framework/Env/Configuration/Resources/Shared/custom_configuration_resource.gd")
const ConfigurationType = preload("res://Framework/Env/Configuration/Resources/Shared/configuration_type_resource.gd")
const Policy = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")
const Authoring = preload("res://Framework/Env/Authoring/Resources/Configuration/custom_configuration_authoring.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const ValueTree = preload("res://Framework/Env/Authoring/Shared/value_tree.gd")

const ROOT := "res://Framework/Content/Configuration/"
const PROFILES_ROOT := "res://Framework/Content/Gameplay/Profiles"


static func supports(path: String, resource: Resource) -> bool:
	return (
		resource is Controls and path.begins_with(ROOT)
		or resource is Movement and is_movement_path(path)
		or resource is Controller and path.begins_with(ControllerAuthoring.ROOT + "/")
		or Policy.is_shared_folder(path.get_base_dir()) and (
			resource is Custom and not path.ends_with(Authoring.TYPE_SUFFIX)
			or resource is ConfigurationType and path.ends_with(Authoring.TYPE_SUFFIX)
		)
	)


static func is_movement_path(path: String) -> bool:
	return path.begins_with(PROFILES_ROOT + "/") or path.begins_with(ROOT)


static func graph(
	path: String,
	resource: Resource,
	hashes: Dictionary,
	browsing: bool
) -> Dictionary:
	if not supports(path, resource):
		return Values.failure("Expected a supported configuration resource.")

	var fields: Dictionary
	var configuration_type: String
	if resource is Controls:
		configuration_type = "input"
		fields = {"Bindings": resource.bindings}
	elif resource is Controller:
		var checked: Dictionary = resource.read()
		if not checked["ok"]:
			return checked
		configuration_type = "movement_controller"
		fields = checked["value"]
	elif resource is ConfigurationType:
		var error: String = resource.validation_error()
		if not error.is_empty():
			return Values.failure(error)
		configuration_type = "custom_type"
		fields = {"Type ID": resource.id, "Label": resource.label, "Fields": resource.fields}
	elif resource is Custom:
		var folder := path.get_base_dir()
		var schema_path := _resource_path(resource.schema)
		if schema_path.get_base_dir() != folder or not schema_path.ends_with(Authoring.TYPE_SUFFIX) or not hashes.has(schema_path):
			return Values.failure("Choose a preset with a saved Configuration Type from the same profile.")
		var checked: Dictionary = resource.read()
		if not checked["ok"]:
			return checked
		configuration_type = "custom"
		fields = {"Type": resource.schema.label, "Type Resource": schema_path, "Values": checked["value"]}
	else:
		configuration_type = "movement"
		var movement := resource as Movement
		var environment := movement.resolved_environment()
		fields = {
			"Behavior": _resource_path(movement.movement_behavior),
			"Velocity Step": movement.velocity_step_id,
			"Input Actions": movement.actions,
			"Pixels Per Unit" if environment.body_type() == "CharacterBody2D" else "Native Units Per Gameplay Unit": environment.units_per_gameplay_unit,
			"Environment": environment.environment_id(),
		}
		if environment.environment_id() == "grid":
			var grid := environment.to_definition()
			var cells: Array[String] = []
			for cell: Vector2i in grid["blocked_cells"]:
				cells.append("%d, %d" % [cell.x, cell.y])
			fields["Grid"] = {
				"Columns": grid["board_size"].x,
				"Rows": grid["board_size"].y,
				"Cell Size in Pixels": grid["cell_size_pixels"],
				"Blocked Cells": cells,
			}
		if movement.movement_action != null:
			fields["Action"] = movement.movement_action.resource_path
			fields["Speed Container"] = movement.speed_container
			fields["Speed Path"] = movement.speed_path

	var state := {"count": 0, "error": ""}
	var tree := ValueTree.build(fields, [], "data", false, state)
	if not state["error"].is_empty():
		return Values.failure(state["error"])
	_complete_read_only_node(tree)

	var checked := Files.check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked

	var node := {
		"id": path.get_file().get_basename(),
		"kind": "configuration",
		"configuration_type": configuration_type,
		"source_path": path,
		"content_hash": hashes[path],
		"links": [],
		"data": tree,
	}
	if resource is Controls:
		node["physical_keys"] = _physical_keys()
	var result := {
		"version": 2,
		"roots": [path],
		"nodes": {path: node},
		"dependency_hashes": hashes,
		"catalog_paths": [],
	}
	if browsing:
		result["mode"] = "browse"
	return Values.success(result)


static func _resource_path(resource: Resource) -> String:
	return resource.resource_path if resource != null else ""


static func _physical_keys() -> Array[Dictionary]:
	var keys: Array[Dictionary] = [
		{"label": "Left Arrow", "code": str(KEY_LEFT)},
		{"label": "Right Arrow", "code": str(KEY_RIGHT)},
		{"label": "Up Arrow", "code": str(KEY_UP)},
		{"label": "Down Arrow", "code": str(KEY_DOWN)},
		{"label": "Space", "code": str(KEY_SPACE)},
	]
	for code in range(KEY_EXCLAM, KEY_ASCIITILDE + 1):
		var label := String.chr(code)
		if label.to_upper() == label:
			keys.append({"label": label, "code": str(code)})
	for code in [KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_ENTER, KEY_KP_ENTER,
		KEY_INSERT, KEY_DELETE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN,
		KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_CAPSLOCK, KEY_PAUSE, KEY_PRINT]:
		keys.append({"label": OS.get_keycode_string(code), "code": str(code)})
	for code in range(KEY_F1, KEY_F35 + 1):
		keys.append({"label": OS.get_keycode_string(code), "code": str(code)})
	for code in range(KEY_KP_0, KEY_KP_9 + 1):
		keys.append({"label": OS.get_keycode_string(code), "code": str(code)})
	return keys


static func _complete_read_only_node(node: Dictionary) -> void:
	node["can_rename"] = false
	node["can_remove"] = false
	node["can_add_effect"] = false
	node["allowed_types"] = []
	node["choices"] = []
	for child: Dictionary in node["children"]:
		_complete_read_only_node(child)
