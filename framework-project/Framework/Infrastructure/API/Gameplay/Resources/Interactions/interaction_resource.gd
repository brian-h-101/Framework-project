extends Resource

const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Actions/action_resource.gd"
)
const ConditionGroupResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd"
)

@export var id: StringName = &""
@export var action: ActionResource
@export var requirements: ConditionGroupResource
@export var arguments: Dictionary = {}


func to_definition() -> Dictionary:
	var requirement_definitions: Array[Dictionary] = []

	if requirements != null:
		requirement_definitions = requirements.to_requirements()

	return {
		"id": id,
		"action": action.id,
		"requirements": requirement_definitions,
		"arguments": arguments.duplicate(true),
	}
