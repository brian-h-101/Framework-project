extends RefCounted


static func definition() -> Dictionary:
	return {
		"id": &"strike",
		"action": &"change_health",
		"requirements": [
			{
				"entity": &"actor",
				"container": &"strength",
				"path": ["current"],
				"operator": ">=",
				"value": 10,
				"message": "Strike requires at least 10 strength.",
			},
		],
		"arguments": {
			&"amount": -10,
		},
	}