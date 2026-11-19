extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"feeding": {
			"diet": "",
			"last_meal_tick": 0,
			"preferred_food_ids": [],
			"satiation": 0
		}
	}
