extends RefCounted

# Example initial evidence data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"evidence": {
			"discovered": {
				"torn_note": {
					"source": "old_bridge",
					"confidence": 0.5,
				},
			},
			"examined_ids": [],
		},
	}
