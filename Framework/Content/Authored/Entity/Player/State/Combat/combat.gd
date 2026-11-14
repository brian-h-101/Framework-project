extends RefCounted

# Example initial combat data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"combat": {
			"team_id": "travelers",
			"damage": 6,
			"armor": 1,
			"defending": false,
			"attack_cost": 1,
			"range": 1,
		},
	}
