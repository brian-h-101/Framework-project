extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"goals": {
			"active_goal_id": "",
			"priorities": {},
			"progress": {}
		}
	}
