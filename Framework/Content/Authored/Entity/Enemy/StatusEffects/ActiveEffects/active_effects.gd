extends RefCounted

# Example initial active effects data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"status_effects": {
			"active": [
				{
					"id": "alert",
					"remaining_ticks": 2,
					"stacks": 1,
					"source": "initial_state",
				},
			],
		},
	}
