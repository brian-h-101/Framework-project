extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"combat": {
			"armor": 0,
			"attack_cost": 0,
			"damage": 0,
			"defending": false,
			"range": 0,
			"team_id": ""
		}
	}
