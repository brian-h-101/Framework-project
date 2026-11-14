extends RefCounted

# Example initial relationships data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"relationships": {
			"records": {
				"patrol_leader": {
					"affinity": 10,
					"trust": 20,
				},
			},
		},
	}
