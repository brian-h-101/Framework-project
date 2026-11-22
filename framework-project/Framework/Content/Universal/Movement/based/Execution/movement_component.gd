extends RefCounted

const WorldBridge = preload("res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd")
const Configuration = preload("res://Framework/Content/Universal/Movement/based/Configuration/movement_profile.gd")
const Controller = preload("res://Framework/Content/Universal/Movement/based/Controllers/movement_controller.gd")
const ControllerRules = preload("res://Framework/Content/Universal/Movement/based/Controllers/controller_rules.gd")
const Adapter = preload("res://Framework/Content/Universal/Movement/based/Execution/movement_adapter.gd")
const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")
const Driver = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_environment.gd")

var _bridge: WorldBridge
var _entity: Node
var _map: Node
var _environment: Driver
var _controller: Controller
var _definition: Dictionary
var _legacy_actions: Dictionary


func configure_entity(bridge: WorldBridge, entity: Node) -> void:
	_bridge = bridge
	_entity = entity


func configure_map(map: Node) -> void:
	_map = map


func start(body: Node, profile: Configuration, controller: Controller) -> String:
	if profile == null or _bridge == null or not is_instance_valid(_entity):
		return "Movement has no configuration or entity context."
	var checked := profile.read()
	if not checked["ok"]:
		return checked["error"]
	var definition: Dictionary = checked["value"]

	var spec := profile.resolved_environment()
	var legacy_actions: Dictionary = {}
	if controller == null:
		if profile.actions.is_empty():
			return "Movement requires a controller."
		var error := ControllerRules.keyboard_error(profile.actions)
		if not error.is_empty():
			return error
		legacy_actions = profile.actions.duplicate(true)
	else:
		checked = controller.read()
		if not checked["ok"]:
			return checked["error"]
		var controller_definition: Dictionary = checked["value"]
		if spec.body_type() == "CharacterBody3D" and controller_definition.get("distance_unit") == "pixels":
			return "3D targeting controllers require stopping distance in gameplay units."

	if not body.is_class(spec.body_type()):
		return "The movement environment requires a %s body." % spec.body_type()
	_environment = spec.create_driver(body, _map, _bridge, _entity)
	if _environment == null:
		return "Could not bind the '%s' movement environment to this map and body." % spec.environment_id()

	_definition = definition
	_controller = controller
	_legacy_actions = legacy_actions
	return ""


func advance(delta: float) -> String:
	var intent := (
		_controller.sample_intent(_read_input, _environment.observe_target)
		if _controller != null else ControllerRules.keyboard_intent(_legacy_actions, _read_input)
	)
	var desired := Adapter.execute(_definition, intent, _invoke_behavior, _execute_action)
	if not desired["ok"]:
		_environment.stop()
		return desired["error"]
	var error := _environment.apply_movement(desired["value"], delta)
	if not error.is_empty():
		_environment.stop()
	return error


func _read_input(actions: Dictionary) -> Dictionary:
	var direction := Input.get_vector(actions["left"], actions["right"], actions["up"], actions["down"])
	return Intent.axes(direction.x, -direction.y)


func _invoke_behavior(id: StringName, step: StringName, arguments: Dictionary) -> Dictionary:
	return _bridge.invoke_behavior(_entity, id, step, arguments)


func _execute_action(id: StringName, arguments: Dictionary) -> Dictionary:
	return _bridge.execute_action(id, _entity, _entity, arguments)
