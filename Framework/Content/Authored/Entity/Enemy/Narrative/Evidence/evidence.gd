extends RefCounted

# Example initial evidence data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"evidence": {
			"discovered": {
				"footprints": {
					"source": "outpost_gate",
					"confidence": 0.5,
				},
			},
			"examined_ids": [],
		},
	}
