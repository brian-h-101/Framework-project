extends RefCounted

# Example initial goals data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"goals": {
			"active_goal_id": "guard_post",
			"priorities": {
				"guard_post": 10,
				"rest": 3,
			},
			"progress": {
				"guard_post": 0,
			},
		},
	}
