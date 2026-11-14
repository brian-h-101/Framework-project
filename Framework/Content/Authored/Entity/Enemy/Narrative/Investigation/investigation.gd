extends RefCounted

# Example initial investigation data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"investigation": {
			"active_case_id": "camp_security",
			"leads": {
				"outpost_gate": {
					"status": "unexamined",
					"evidence_ids": [
						"footprints",
					],
				},
			},
			"conclusions": [],
		},
	}
