extends RefCounted

const EntitySceneDefaults = preload(
	"res://Framework/Content/Configuration/Presentation/entity_scene_defaults.gd"
)


static func defaults() -> Dictionary:
	var definition := EntitySceneDefaults.defaults()
	definition["body_size"] = Vector2(12, 40)
	definition["body_color"] = Color(0.75, 0.8, 0.85, 1.0)
	return definition
