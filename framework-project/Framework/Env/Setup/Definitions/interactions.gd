extends RefCounted

const ResourceDefinitionDiscovery = preload(
	"res://Framework/Env/Setup/Discovery/resource_definition_discovery.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd"
)


static func definitions() -> Dictionary:
	return ResourceDefinitionDiscovery.profile_definitions(InteractionResource)
