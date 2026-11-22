extends RefCounted

const ResourceDefinitionDiscovery = preload(
	"res://Framework/Env/Setup/Discovery/resource_definition_discovery.gd"
)
const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Actions/action_resource.gd"
)


static func definitions() -> Dictionary:
	return ResourceDefinitionDiscovery.profile_definitions(ActionResource)
