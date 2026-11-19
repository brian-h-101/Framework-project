extends RefCounted

const ContentDiscovery = preload(
	"res://Framework/Env/Setup/content_discovery.gd"
)


static func definitions() -> Dictionary:
	return ContentDiscovery.entity_definitions_in(
		"res://Framework/Content/Presentation/Entity"
	)
