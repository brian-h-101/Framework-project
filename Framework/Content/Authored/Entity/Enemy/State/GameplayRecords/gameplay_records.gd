extends RefCounted

# Example initial gameplay records data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"gameplay_records": {
			"counters": {
				"encounters_won": 0,
				"items_collected": 0,
				"locations_discovered": 1,
			},
			"last_event": "",
		},
	}
