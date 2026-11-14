extends RefCounted

# Example initial journal data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"journal": {
			"entries": [
				{
					"id": "arrival",
					"title": "Arrival",
					"text": "Reached the village.",
					"tick": 0,
				},
			],
			"pinned_entry_ids": [],
		},
	}
