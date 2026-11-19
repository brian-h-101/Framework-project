extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"activity": {
			"current": "",
			"interrupted": false,
			"progress": 0,
			"started_tick": 0
		}
	}
