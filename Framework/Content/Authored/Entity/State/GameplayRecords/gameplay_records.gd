extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"gameplay_records": {
			"counters": {},
			"last_event": ""
		}
	}
