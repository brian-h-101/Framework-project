extends RefCounted

# Example initial knowledge data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"knowledge": {
			"facts": {
				"bridge_damaged": true,
			},
			"learned_from": {
				"bridge_damaged": "observation",
			},
			"last_updated_tick": 0,
		},
	}
