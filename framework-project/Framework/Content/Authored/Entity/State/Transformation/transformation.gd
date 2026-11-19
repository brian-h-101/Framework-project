extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"transformation": {
			"active": false,
			"available_form_ids": [],
			"cooldown_remaining": 0,
			"current_form_id": "",
			"previous_form_id": ""
		}
	}
