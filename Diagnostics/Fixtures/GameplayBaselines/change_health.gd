extends RefCounted


static func definition() -> Dictionary:
	return {
		"id": &"change_health",
		"effects": [
			{
				"operation": &"add",
				"entity": &"target",
				"container": &"health",
				"path": ["current"],
				"value_from": &"amount",
			},
		],
	}