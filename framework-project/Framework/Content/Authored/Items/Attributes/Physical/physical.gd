extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"physical": {
			"weight_kg": 0.0,
			"volume_liters": 0.0,
		},
	}
