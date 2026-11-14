extends RefCounted

# Example initial combat data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"combat": {
			"team_id": "raiders",
			"damage": 4,
			"armor": 2,
			"defending": false,
			"attack_cost": 1,
			"range": 1,
		},
	}
