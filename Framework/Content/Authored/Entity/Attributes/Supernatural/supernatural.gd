extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"supernatural": {
			"origin": "",
			"resource": {
				"current": 0,
				"id": &"",
				"maximum": 0
			},
			"traits": []
		}
	}
