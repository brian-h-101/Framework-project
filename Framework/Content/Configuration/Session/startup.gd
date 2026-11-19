extends RefCounted


static func defaults() -> Dictionary:
	return {
		"initial_map": "res://Games/ExampleGame/World/city_recreated.tscn",
		"entities": {
			&"player": {
				"definition": &"player",
				"overrides": {
					&"health": {"current": 75},
					&"strength": {"current": 80},
				},
			},
			&"second_player": {
				"definition": &"player",
			},
			&"enemy": {
				"definition": &"enemy",
			},
		},
	}
