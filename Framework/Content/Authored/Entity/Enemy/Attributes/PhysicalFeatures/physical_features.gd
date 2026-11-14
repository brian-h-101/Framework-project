extends RefCounted

# Example initial physical features data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"physical_features": {
			"age": 35,
			"height_cm": 182,
			"eye_color": "grey",
			"distinguishing_marks": [
				"scar_left_brow",
			],
		},
	}
