extends RefCounted

# Example initial life experience data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"life_experience": {
			"background": "traveler",
			"education": [
				"basic_literacy",
			],
			"employment": [
				{
					"role": "courier",
					"years": 2,
				},
			],
			"milestones": [
				"first_journey",
			],
		},
	}
