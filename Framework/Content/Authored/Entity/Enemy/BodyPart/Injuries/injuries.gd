extends RefCounted

# Example initial injuries data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"injuries": {
			"active": [
				{
					"id": "minor_bruise",
					"body_part": "right_arm",
					"severity": 1,
					"treated": false,
				},
			],
			"healed_ids": [],
		},
	}
