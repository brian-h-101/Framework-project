extends "res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd"

const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Actions/action_resource.gd"
)
const BehaviorResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd"
)
const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")
const EnvironmentSpec = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_environment_spec.gd")
const Compatibility = preload("res://Framework/Content/Universal/Movement/based/Configuration/movement_environment_compatibility.gd")

@export var movement_action: ActionResource
@export var actions: Dictionary = {}
@export var speed_container: StringName = &""
@export var speed_path: Array[String] = []
@export_storage var pixels_per_unit: float = 0.0
@export var movement_behavior: BehaviorResource
@export var velocity_step_id: StringName = &""
@export var environment_spec: EnvironmentSpec
# Serialized by older profiles.
@export_storage var grid: EnvironmentSpec


func environment() -> String:
	return resolved_environment().environment_id()


func resolved_environment() -> EnvironmentSpec:
	return Compatibility.resolve(environment_spec, grid, pixels_per_unit)


func set_environment_scale(scale: float) -> void:
	environment_spec = resolved_environment().duplicate() as EnvironmentSpec
	environment_spec.units_per_gameplay_unit = scale
	pixels_per_unit = 0.0
	grid = null


func to_definition() -> Dictionary:
	var step := velocity_step()
	var spec := resolved_environment()
	return {
		"action_id": movement_action.id if movement_action != null else &"",
		"behavior_id": movement_behavior.id if movement_behavior != null else &"",
		"velocity_step_id": velocity_step_id,
		"legacy_planar": not Intent.has_axes(step.get("arguments", {}), Intent.AXES),
		"environment": spec.environment_id(),
		"environment_settings": spec.to_definition(),
		"actions": actions.duplicate(true),
		"speed": {
			"container": speed_container,
			"path": speed_path.duplicate(),
			"pixels_per_unit": spec.units_per_gameplay_unit,
		},
	}


func validation_error() -> String:
	if movement_behavior == null:
		if movement_action == null:
			return "Movement requires a Behavior or Action resource."
		if String(movement_action.id).strip_edges().is_empty():
			return "Movement Action requires a nonempty ID."
	else:
		if movement_action != null:
			return "Choose one movement Behavior or Action."
		var error := _behavior_error()
		if not error.is_empty():
			return error

	if movement_action != null or not actions.is_empty():
		for direction in ["left", "right", "up", "down"]:
			if not is_text(actions.get(direction)) or String(actions[direction]).is_empty():
				return "Movement requires a nonempty %s action." % direction
	var error := resolved_environment().validation_error()
	if not error.is_empty():
		return error
	return attribute_error(to_definition()["speed"]) if movement_behavior == null else ""


func _behavior_error() -> String:
	var checked := movement_behavior.read()
	if not checked["ok"]:
		return checked["error"]

	var definition: Dictionary = checked["value"]
	var configuration: Dictionary = definition["configuration"]
	if (
		configuration["trigger"] != "manual"
		or configuration["targeting"] != "self"
		or configuration["cooldown_seconds"] != 0.0
	):
		return "Movement requires a manual, self-targeted Behavior with zero cooldown."

	var arguments: Dictionary = _velocity_step(definition["steps"]).get("arguments", {})
	if Intent.has_axes(arguments, Intent.AXES) or Intent.has_axes(arguments, Intent.LEGACY_AXES):
		return ""
	return "Movement requires a velocity Action Step with lateral, forward and vertical arguments or legacy planar arguments."


func velocity_step() -> Dictionary:
	if movement_behavior == null:
		return {}
	var checked := movement_behavior.read()
	return _velocity_step(checked["value"]["steps"]) if checked["ok"] else {}


func _velocity_step(steps: Array) -> Dictionary:
	var pending := steps.duplicate()
	while not pending.is_empty():
		var step: Dictionary = pending.pop_back()
		if step["kind"] == "group":
			pending.append_array(step["steps"])
		elif step["id"] == velocity_step_id:
			return step
	return {}
