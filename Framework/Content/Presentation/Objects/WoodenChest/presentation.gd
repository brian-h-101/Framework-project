extends RefCounted

const EntitySceneDefaults = preload(
	"res://Framework/Content/Configuration/Presentation/entity_scene_defaults.gd"
)


static func defaults() -> Dictionary:
	var definition := EntitySceneDefaults.defaults()
	definition["body_size"] = Vector2(48, 32)
	definition["body_color"] = Color(0.55, 0.32, 0.14, 1.0)
	return definition
