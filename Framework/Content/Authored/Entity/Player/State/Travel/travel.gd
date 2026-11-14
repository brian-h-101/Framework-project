extends RefCounted

# Example initial travel data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"travel": {
			"current_location_id": "village_square",
			"known_location_ids": [
				"village_square",
			],
			"destination_id": "",
			"progress": 0,
			"vehicle_id": "",
		},
	}
