extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"investigation": {
			"active_case_id": "",
			"conclusions": [],
			"leads": {}
		}
	}
