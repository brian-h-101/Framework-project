extends RefCounted

# Example initial quest progress data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"quest_progress": {
			"quests": {
				"delivery": {
					"stage": "not_started",
					"objectives": {
						"supplies_delivered": 0,
					},
					"reward_claimed": false,
				},
			},
		},
	}
