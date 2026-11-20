extends RefCounted

const ResourceDefinitionDiscovery = preload(
	"res://Framework/Env/Setup/resource_definition_discovery.gd"
)
const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/action_resource.gd"
)


static func definitions() -> Dictionary:
	return ResourceDefinitionDiscovery.definitions_in(
		"res://Framework/Content/Behavior/Action",
		ActionResource
	)
