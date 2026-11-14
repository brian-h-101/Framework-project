extends RefCounted

# Example initial injuries data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"injuries": {
			"active": [
				{
					"id": "minor_bruise",
					"body_part": "left_arm",
					"severity": 1,
					"treated": false,
				},
			],
			"healed_ids": [],
		},
	}
