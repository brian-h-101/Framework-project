extends RefCounted

const ResourceDefinitionDiscovery = preload(
	"res://Framework/Env/Setup/resource_definition_discovery.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd"
)


static func definitions() -> Dictionary:
	return ResourceDefinitionDiscovery.definitions_in(
		"res://Framework/Content/Interaction",
		InteractionResource
	)
