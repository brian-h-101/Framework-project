extends RefCounted


static func defaults() -> Dictionary:
	return {
		"actions": {
			"left": &"move_left",
			"right": &"move_right",
			"up": &"move_up",
			"down": &"move_down",
		},
		"speed": {
			"container": &"speed",
			"path": ["current"],
			"pixels_per_unit": 10.0,
		},
	}