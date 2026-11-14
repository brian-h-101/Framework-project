extends RefCounted

# Example initial forms data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"forms": {
			"definitions": {
				"human": {
					"display_name": "Human",
					"body_plan": "humanoid",
				},
				"wolf": {
					"display_name": "Wolf",
					"body_plan": "quadruped",
				},
			},
			"unlocked_ids": [
				"human",
			],
		},
	}
