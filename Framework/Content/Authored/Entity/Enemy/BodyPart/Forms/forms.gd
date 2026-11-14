extends RefCounted

# Example initial forms data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"forms": {
			"definitions": {
				"human": {
					"display_name": "Human",
					"body_plan": "humanoid",
				},
			},
			"unlocked_ids": [
				"human",
			],
		},
	}
