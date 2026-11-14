extends RefCounted

# Example initial anatomy data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"anatomy": {
			"body_plan": "humanoid",
			"dominant_hand": "right",
			"parts": [
				"head",
				"torso",
				"left_arm",
				"right_arm",
				"left_hand",
				"right_hand",
				"left_leg",
				"right_leg",
			],
		},
	}
