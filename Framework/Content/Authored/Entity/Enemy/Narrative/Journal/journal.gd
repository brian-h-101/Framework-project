extends RefCounted

# Example initial journal data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"journal": {
			"entries": [
				{
					"id": "watch_started",
					"title": "On Watch",
					"text": "Assigned to watch the outpost.",
					"tick": 0,
				},
			],
			"pinned_entry_ids": [],
		},
	}
