extends RefCounted

# Example initial feeding data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"feeding": {
			"diet": "omnivore",
			"preferred_food_ids": [
				"ration",
			],
			"last_meal_tick": 0,
			"satiation": 90,
		},
	}
