extends RefCounted

# Example initial travel data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"travel": {
			"current_location_id": "outpost_gate",
			"known_location_ids": [
				"outpost_gate",
			],
			"destination_id": "",
			"progress": 0,
			"vehicle_id": "",
		},
	}
