extends RefCounted

# Example initial transformation data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"transformation": {
			"current_form_id": "human",
			"previous_form_id": "",
			"active": false,
			"available_form_ids": [
				"human",
			],
			"cooldown_remaining": 0,
		},
	}
