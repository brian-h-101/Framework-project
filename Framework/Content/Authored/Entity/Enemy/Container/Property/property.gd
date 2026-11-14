extends RefCounted

# Example initial property data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"property": {
			"owned": [],
			"rented": [
				{
					"id": "outpost_bunk",
					"rent_per_day": 2,
				},
			],
		},
	}
