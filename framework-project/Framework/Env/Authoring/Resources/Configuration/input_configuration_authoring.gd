extends RefCounted

const Controls = preload("res://Framework/Env/Configuration/Resources/Input/controls_resource.gd")
const Inspection = preload("res://Framework/Env/Authoring/Resources/Configuration/configuration_inspection.gd")
const Library = preload("res://Framework/Env/Authoring/Resources/Library/behavior_library.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")

const OPERATIONS := ["add_input_binding", "set_input_binding_keys", "remove_input_binding"]


static func edit(path: String, request: Dictionary) -> Dictionary:
	if not path.begins_with(Inspection.ROOT):
		return Values.failure("Choose a Controls resource under Content/Configuration.")

	var hashes := {}
	var checked := Library._hash_resources(path, hashes, 0)
	if not checked["ok"]:
		return checked

	var expected: Variant = request.get("expected_hashes")
	if not expected is Dictionary:
		return Values.failure("Input edits require inspected resource hashes.")

	checked = Files.check_hashes(expected, hashes)
	if not checked["ok"]:
		return checked

	var controls := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Controls
	if controls == null:
		return Values.failure("Expected a Controls resource.")

	checked = _apply(controls, request)
	if not checked["ok"]:
		return checked

	checked = controls.read()
	if not checked["ok"]:
		return checked

	return Files.save(path, hashes, controls, _snapshot)


static func _apply(controls: Controls, request: Dictionary) -> Dictionary:
	var operation: Variant = request.get("operation")
	if operation not in OPERATIONS:
		return Values.failure("Unknown input binding operation.")

	var action: Variant = request.get("action")
	if not action is String:
		return Values.failure("Enter an input action name.")
	var adding: bool = operation == "add_input_binding"
	var action_name := String(action).strip_edges() if adding else String(action)
	if action_name.is_empty():
		return Values.failure("Enter an input action name.")
	var action_id := StringName(action_name)

	var index := -1
	for candidate in controls.bindings.size():
		var stored: Variant = controls.bindings[candidate].get("action")
		if typeof(stored) in [TYPE_STRING, TYPE_STRING_NAME] and StringName(stored) == action_id:
			index = candidate
			break

	if adding and index != -1:
		return Values.failure("Input action already exists: %s" % action_id)
	if not adding and index == -1:
		return Values.failure("Input action does not exist: %s" % action_id)

	if operation == "remove_input_binding":
		controls.bindings.remove_at(index)
		return Values.success(true)

	var parsed := _parse_keys(request.get("key_codes"))
	if not parsed["ok"]:
		return parsed

	if adding:
		controls.bindings.append({"action": action_id, "keys": parsed["value"]})
	else:
		controls.bindings[index]["keys"] = parsed["value"]
	return Values.success(true)


static func _parse_keys(values: Variant) -> Dictionary:
	if not values is Array or values.is_empty():
		return Values.failure("Choose at least one physical key.")

	var keys: Array[int] = []
	for value in values:
		if not value is String:
			return Values.failure("Expected key codes as integer text.")
		var parsed := Values.parse("int", value)
		if not parsed["ok"] or parsed["value"] <= 0:
			return Values.failure("Physical key codes must be positive integers.")
		var key: int = parsed["value"]
		if keys.has(key):
			return Values.failure("Choose each physical key once.")
		keys.append(key)
	return Values.success(keys)


static func _snapshot(resource: Resource) -> Dictionary:
	if not resource is Controls:
		return {}
	var metadata := {}
	for key in resource.get_meta_list():
		metadata[key] = resource.get_meta(key)
	return {
		"script": resource.get_script().resource_path,
		"bindings": resource.bindings,
		"resource_name": resource.resource_name,
		"resource_local_to_scene": resource.resource_local_to_scene,
		"metadata": metadata,
	}
