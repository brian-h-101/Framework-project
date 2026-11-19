extends RefCounted

const ContentDiscovery = preload(
	"res://Framework/Env/Setup/content_discovery.gd"
)


static func definitions() -> Dictionary:
	return ContentDiscovery.starting_definitions_in(PackedStringArray([
		"res://Framework/Content/Presentation/Entity",
		"res://Framework/Content/Presentation/Items",
		"res://Framework/Content/Presentation/Objects",
	]))
