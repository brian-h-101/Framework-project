extends RefCounted

const ResourceDefinitionDiscovery = preload(
	"res://Framework/Env/Setup/resource_definition_discovery.gd"
)
const AutomationResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/automation_resource.gd"
)


static func definitions() -> Dictionary:
	return ResourceDefinitionDiscovery.definitions_in(
		"res://Framework/Content/Behavior",
		AutomationResource
	)
