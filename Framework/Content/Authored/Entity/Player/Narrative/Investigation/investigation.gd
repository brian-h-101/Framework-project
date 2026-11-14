extends RefCounted

# Example initial investigation data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"investigation": {
			"active_case_id": "missing_supplies",
			"leads": {
				"old_bridge": {
					"status": "unexamined",
					"evidence_ids": [
						"torn_note",
					],
				},
			},
			"conclusions": [],
		},
	}
