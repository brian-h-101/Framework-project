extends RefCounted

const EntitySceneDefaults = preload(
	"res://Framework/Content/Configuration/Presentation/entity_scene_defaults.gd"
)


static func defaults() -> Dictionary:
	var definition := EntitySceneDefaults.defaults()

	definition["body_color"] = Color(0.2, 0.6, 1.0, 1.0)

	definition["movement_content"] = preload(
		"res://Framework/Content/Configuration/Movement/player_movement.gd"
	)

	definition["camera_scene"] = preload(
		"res://Framework/Content/Camera/player_camera_2d.tscn"
	)

	definition["interaction_input"] = true

	return definition
