extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"crime": {
			"bounty": 0,
			"jurisdiction_id": "",
			"offenses": [],
			"wanted": false
		}
	}
