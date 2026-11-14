extends RefCounted

# Example initial relationships data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"relationships": {
			"records": {
				"village_guard": {
					"affinity": 0,
					"trust": 0,
				},
			},
		},
	}
