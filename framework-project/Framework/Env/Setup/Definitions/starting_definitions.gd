extends RefCounted

const ContentDiscovery = preload(
	"res://Framework/Env/Setup/Discovery/content_discovery.gd"
)


static func definitions() -> Dictionary:
	return ContentDiscovery.starting_definitions_in(PackedStringArray([
		"res://Framework/Content/Gameplay/Presentation/Entity",
		"res://Framework/Content/Gameplay/Presentation/Items",
		"res://Framework/Content/Gameplay/Presentation/Objects",
	]))
