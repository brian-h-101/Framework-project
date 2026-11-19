extends RefCounted

const Shadows = preload(
	"res://Framework/Content/Configuration/Lighting/shadows.gd"
)


static func defaults() -> Dictionary:
	return {
		"ambient_color": Color(0.45, 0.50, 0.65, 1.0),
		"shadows": Shadows.defaults(),
		"day_night": {
			"sunrise": 0.25,
			"sunset": 0.75,
			"night_ambient": Color(0.12, 0.15, 0.25, 1.0),
			"day_ambient": Color(0.55, 0.60, 0.65, 1.0),
			"sun": {
				"color": Color(1.0, 0.95, 0.85, 1.0),
				"maximum_energy": 0.45,
				"sunrise_angle": -75.0,
				"sunset_angle": 75.0,
			},
		},
		"point_lights": [
			{
				"id": &"courtyard_light",
				"position": Vector2(480, 320),
				"color": Color(1.0, 0.85, 0.65, 1.0),
				"energy": 1.0,
				"radius": 240.0,
			},
		],
	}