extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"physical_features": {
			"age": 0,
			"distinguishing_marks": [],
			"eye_color": "",
			"height_cm": 0
		}
	}
