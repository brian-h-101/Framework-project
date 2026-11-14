extends RefCounted

# Example initial goals data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"goals": {
			"active_goal_id": "explore",
			"priorities": {
				"explore": 10,
				"rest": 5,
			},
			"progress": {
				"explore": 0,
			},
		},
	}
