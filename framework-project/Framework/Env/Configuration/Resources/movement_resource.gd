extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/action_resource.gd"
)

@export var movement_action: ActionResource
@export var actions: Dictionary = {}
@export var speed_container: StringName = &""
@export var speed_path: Array[String] = []
@export var pixels_per_unit: float = 0.0


func to_definition() -> Dictionary:
	return {
		"action_id": movement_action.id if movement_action != null else &"",
		"actions": actions.duplicate(true),
		"speed": {
			"container": speed_container,
			"path": speed_path.duplicate(),
			"pixels_per_unit": pixels_per_unit,
		},
	}


func validation_error() -> String:
	if movement_action == null:
		return "Movement requires an Action resource."

	if String(movement_action.id).strip_edges().is_empty():
		return "Movement Action requires a nonempty ID."

	for direction in ["left", "right", "up", "down"]:
		if not is_text(actions.get(direction)) or String(actions[direction]).is_empty():
			return "Movement requires a nonempty %s action." % direction
	if not is_finite(pixels_per_unit) or pixels_per_unit <= 0.0:
		return "Pixels per speed unit must be positive and finite."
	return attribute_error(to_definition()["speed"])
