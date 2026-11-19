extends RefCounted

const EntitySceneDefaults = preload(
	"res://Framework/Content/Configuration/Presentation/entity_scene_defaults.gd"
)


static func defaults() -> Dictionary:
	var definition := EntitySceneDefaults.defaults()

	definition["body_color"] = Color(0.9, 0.25, 0.2, 1.0)

	return definition
