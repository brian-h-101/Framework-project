extends RefCounted

# Example initial activities data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"activity": {
			"current": "idle",
			"progress": 0,
			"started_tick": 0,
			"interrupted": false,
		},
	}
