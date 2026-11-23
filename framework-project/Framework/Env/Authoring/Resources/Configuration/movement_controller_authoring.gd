extends RefCounted

const Controller = preload("res://Framework/Content/Universal/Movement/based/Controllers/movement_controller.gd")
const Keyboard = preload("res://Framework/Content/Universal/Movement/based/Controllers/keyboard_movement_controller.gd")
const AI = preload("res://Framework/Content/Universal/Movement/based/Controllers/ai_movement_controller.gd")
const Controls = preload("res://Framework/Env/Configuration/Resources/Input/controls_resource.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Drafts = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")

const ROOT := "res://Framework/Content/Gameplay/Controller"
const INPUT := "res://Framework/Content/Configuration/Input/controls.tres"
const OPERATION := "draft_movement_controller"


static func draft(path: String, request: Dictionary) -> Dictionary:
	if path.get_base_dir() != ROOT or path.get_extension() != "tres":
		return Values.failure("Create a movement controller .tres directly in Content/Gameplay/Controller.")
	var error := Paths.name_error(path.get_file())
	if error.is_empty():
		error = Paths.project_error(path)
	if not error.is_empty():
		return Values.failure(error)

	var expected: Variant = request.get("expected_hashes")
	if not expected is Dictionary:
		return Values.failure("Movement controller drafts require inspected resource hashes.")
	var required := {}
	var controller: Controller
	match request.get("controller_kind"):
		"keyboard":
			required[INPUT] = true
			var checked := Files.check_hashes(expected, required)
			if not checked["ok"]:
				return checked
			var keyboard := Keyboard.new()
			checked = _configure_keyboard(keyboard, request.get("input_actions"))
			if not checked["ok"]:
				return checked
			controller = keyboard
		"ai":
			var targeting: Variant = request.get("targeting")
			var distance_unit: Variant = request.get("distance_unit")
			var stopping_distance: Variant = request.get("stopping_distance")
			if not targeting is String or not distance_unit is String or not Controller.is_number(stopping_distance):
				return Values.failure("Choose a targeting mode, a distance unit, and a finite stopping distance.")
			var ai := AI.new()
			ai.targeting = targeting
			ai.distance_unit = distance_unit
			ai.stopping_distance = float(stopping_distance)
			controller = ai
		_:
			return Values.failure("Choose a Keyboard Movement or AI Movement controller.")

	var checked := controller.read()
	if not checked["ok"]:
		return checked
	var result := Drafts.draft(path, request.get("expected_parent"), controller, _snapshot)
	if not result["ok"]:
		return result
	checked = Files.check_hashes(expected, required)
	return result if checked["ok"] else checked


static func _configure_keyboard(controller: Keyboard, actions: Variant) -> Dictionary:
	if not actions is Dictionary:
		return Values.failure("Choose the keyboard controller's directional actions.")
	var controls := ResourceLoader.load(INPUT, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Controls
	if controls == null:
		return Values.failure("Could not load the project's Controls resource.")
	var checked := controls.read()
	if not checked["ok"]:
		return checked
	var bindings: Dictionary = checked["value"]
	for direction: String in Keyboard.DIRECTIONS:
		var action: Variant = actions.get(direction)
		if not action is String or not bindings.has(StringName(action)) or bindings[StringName(action)]["keys"].is_empty():
			return Values.failure("Choose an input action with at least one bound key for %s." % direction)
		controller.actions[direction] = StringName(action)
	return Values.success(true)


static func _snapshot(resource: Controller) -> Dictionary:
	return resource.to_definition()
