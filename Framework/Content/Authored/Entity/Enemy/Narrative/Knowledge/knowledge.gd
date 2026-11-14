extends RefCounted

# Example initial knowledge data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"knowledge": {
			"facts": {
				"camp_route_known": true,
			},
			"learned_from": {
				"camp_route_known": "briefing",
			},
			"last_updated_tick": 0,
		},
	}
