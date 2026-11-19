extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"residency": {
			"permitted_zones": [],
			"residence_id": "",
			"status": ""
		}
	}
