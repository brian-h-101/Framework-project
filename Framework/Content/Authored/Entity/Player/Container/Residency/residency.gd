extends RefCounted

# Example initial residency data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"residency": {
			"residence_id": "village_room",
			"status": "resident",
			"permitted_zones": [
				"village",
			],
		},
	}
