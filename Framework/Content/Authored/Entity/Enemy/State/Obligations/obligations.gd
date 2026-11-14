extends RefCounted

# Example initial obligations data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"obligations": {
			"entries": [
				{
					"id": "daily_upkeep",
					"due_tick": 24,
					"repeat_every_ticks": 24,
					"amount": 2,
					"currency": "coin",
					"status": "pending",
				},
			],
			"last_completed_tick": 0,
		},
	}
