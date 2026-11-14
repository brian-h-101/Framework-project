extends RefCounted

# Example initial residency data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"residency": {
			"residence_id": "outpost_bunk",
			"status": "lodger",
			"permitted_zones": [
				"outpost",
			],
		},
	}
