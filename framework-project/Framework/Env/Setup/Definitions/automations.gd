extends RefCounted

const ResourceDefinitionDiscovery = preload(
	"res://Framework/Env/Setup/Discovery/resource_definition_discovery.gd"
)
const AutomationResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Automation/automation_resource.gd"
)


static func definitions() -> Dictionary:
	return ResourceDefinitionDiscovery.profile_definitions(AutomationResource)
