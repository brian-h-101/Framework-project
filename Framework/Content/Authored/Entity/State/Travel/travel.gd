extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"travel": {
			"current_location_id": "",
			"destination_id": "",
			"known_location_ids": [],
			"progress": 0,
			"vehicle_id": ""
		}
	}
