extends RefCounted

const Movement = preload("res://Framework/Content/Universal/Movement/based/Configuration/movement_profile.gd")
const Behavior = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")
const Controls = preload("res://Framework/Env/Configuration/Resources/Input/controls_resource.gd")
const Inspection = preload("res://Framework/Env/Authoring/Resources/Configuration/configuration_inspection.gd")
const Library = preload("res://Framework/Env/Authoring/Resources/Library/behavior_library.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Drafts = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Names = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")

const INPUT := "res://Framework/Content/Configuration/Input/controls.tres"
const MOVEMENT_FOLDER := Inspection.PROFILES_ROOT + "/Movement/Shared"
const OPERATIONS := ["draft_movement_configuration", "set_movement_configuration"]


static func edit(path: String, request: Dictionary) -> Dictionary:
	if not Inspection.is_movement_path(path) or path.get_extension() != "tres":
		return Values.failure("Choose a Movement resource under Content/Gameplay/Profiles or Content/Configuration.")
	var error := Paths.project_error(path)
	if not error.is_empty():
		return Values.failure(error)

	var selected: Variant = request.get("movement_behavior_path")
	if not selected is String:
		return Values.failure("Choose a saved movement Behavior.")
	error = Names.resource_error(selected)
	if not error.is_empty():
		return Values.failure(error)
	var expected: Variant = request.get("expected_hashes")
	if not expected is Dictionary:
		return Values.failure("Movement edits require inspected resource hashes.")

	var creating: bool = request["operation"] == "draft_movement_configuration"
	var hashes := {}
	var required: Array[String] = [selected]
	if request.has("input_actions"):
		required.append(INPUT)
	if creating:
		if path.get_base_dir() != MOVEMENT_FOLDER:
			return Values.failure("Create Movement profiles in Content/Gameplay/Profiles/Movement/Shared.")
		error = Names.name_error(path.get_file())
		if not error.is_empty():
			return Values.failure(error)
	else:
		required.append(path)
	for source in required:
		var guarded := Library._hash_resources(source, hashes, 0)
		if not guarded["ok"]:
			return guarded

	var checked := Files.check_hashes(expected, hashes)
	if not checked["ok"]:
		return checked
	var movement := Movement.new() if creating else ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Movement
	if movement == null:
		return Values.failure("Expected a Movement resource.")
	if not creating and movement.actions.is_empty() and request.has("input_actions"):
		return Values.failure("A shared Movement profile gets its input mapping from a controller.")
	checked = _configure(movement, selected, request)
	if not checked["ok"]:
		return checked
	if not creating:
		return Files.save(path, hashes, movement, _snapshot)

	var draft := Drafts.draft(path, request.get("expected_parent"), movement, _snapshot)
	if not draft["ok"]:
		return draft
	checked = Files.check_hashes(hashes, hashes)
	return draft if checked["ok"] else checked


static func _configure(movement: Movement, behavior_path: String, request: Dictionary) -> Dictionary:
	var behavior := ResourceLoader.load(behavior_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Behavior
	if behavior == null:
		return Values.failure("Expected a unified movement Behavior.")
	var step: Variant = request.get("velocity_step_id")
	var scale: Variant = request.get("pixels_per_unit")
	if not step is String or not Movement.is_number(scale) or scale <= 0:
		return Values.failure("Choose a velocity step and a positive pixel scale.")
	if request.has("input_actions"):
		var configured := _legacy_actions(movement.actions, request["input_actions"])
		if not configured["ok"]:
			return configured
		movement.actions = configured["value"]

	movement.movement_action = null
	movement.movement_behavior = behavior
	movement.velocity_step_id = StringName(step)
	movement.set_environment_scale(float(scale))
	return movement.read()


static func _legacy_actions(previous: Dictionary, actions: Variant) -> Dictionary:
	if not actions is Dictionary:
		return Values.failure("Choose keyboard input actions.")
	var controls := ResourceLoader.load(INPUT, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Controls
	if controls == null:
		return Values.failure("Could not load the project's Controls resource.")
	var checked := controls.read()
	if not checked["ok"]:
		return checked

	var bindings: Dictionary = checked["value"]
	var configured := previous.duplicate(true)
	for direction in ["left", "right", "up", "down"]:
		var action: Variant = actions.get(direction)
		if not action is String or not bindings.has(StringName(action)):
			return Values.failure("Choose an existing input action for %s." % direction)
		configured[direction] = StringName(action)

	return Values.success(configured)


static func _snapshot(resource: Resource) -> Dictionary:
	if not resource is Movement:
		return {}
	var metadata := {}
	for key in resource.get_meta_list():
		metadata[key] = resource.get_meta(key)
	return {
		"script": resource.get_script().resource_path,
		"definition": resource.to_definition(),
		"movement_behavior": resource.movement_behavior,
		"resource_name": resource.resource_name,
		"resource_local_to_scene": resource.resource_local_to_scene,
		"metadata": metadata,
	}
