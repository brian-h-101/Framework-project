extends RefCounted

# Example initial physical features data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"physical_features": {
			"age": 28,
			"height_cm": 175,
			"eye_color": "brown",
			"distinguishing_marks": [],
		},
	}
