extends RefCounted

# Example initial quest progress data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"quest_progress": {
			"quests": {
				"guard_post": {
					"stage": "active",
					"objectives": {
						"intruders_spotted": 0,
					},
					"reward_claimed": false,
				},
			},
		},
	}
