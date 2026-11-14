extends RefCounted

# Example initial treatments data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"treatments": {
			"known": {
				"bandage": {
					"target": "wound",
					"healing_per_tick": 1,
					"duration_ticks": 3,
				},
				"rest": {
					"target": "fatigue",
					"recovery_per_tick": 2,
					"duration_ticks": 4,
				},
			},
			"active": [],
		},
	}
