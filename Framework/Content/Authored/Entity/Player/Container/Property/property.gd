extends RefCounted

# Example initial property data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"property": {
			"owned": [
				{
					"id": "village_room",
					"type": "room",
					"share": 1,
				},
			],
			"rented": [],
		},
	}
