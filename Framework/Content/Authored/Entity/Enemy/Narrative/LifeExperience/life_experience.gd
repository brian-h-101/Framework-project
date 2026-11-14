extends RefCounted

# Example initial life experience data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"life_experience": {
			"background": "scout",
			"education": [
				"basic_literacy",
			],
			"employment": [
				{
					"role": "guard",
					"years": 3,
				},
			],
			"milestones": [
				"first_patrol",
			],
		},
	}
