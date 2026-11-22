extends Resource

const ConditionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd"
)

const OPERATOR: StringName = &"all"

@export var id: StringName = &""
@export var conditions: Array[ConditionResource] = []


func to_requirements() -> Array[Dictionary]:
	var requirements: Array[Dictionary] = []

	for condition in conditions:
		requirements.append(condition.to_definition())

	return requirements