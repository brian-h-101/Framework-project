extends RefCounted


static func defaults() -> Dictionary:
	return {
		"ground_content": preload(
			"res://Framework/Content/Configuration/Map/city_ground.gd"
		),
		"lighting_content": preload(
			"res://Framework/Content/Configuration/Lighting/city_lighting.gd"
		),
	}