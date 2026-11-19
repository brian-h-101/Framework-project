extends RefCounted

const EntitySceneDefaults = preload(
	"res://Framework/Content/Configuration/Presentation/entity_scene_defaults.gd"
)


static func defaults() -> Dictionary:
	return EntitySceneDefaults.defaults()
