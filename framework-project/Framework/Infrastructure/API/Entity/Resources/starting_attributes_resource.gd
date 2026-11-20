extends Resource

const StartingAttributes = preload(
	"res://Framework/Env/Setup/starting_attributes.gd"
)
const ContainerFragmentResource = preload(
	"res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd"
)

@export var id: StringName = &""
@export var fragments: Array[ContainerFragmentResource] = []
@export var overrides: Dictionary = {}


func to_definition() -> Dictionary:
	return StartingAttributes.define(id, fragments, overrides)
