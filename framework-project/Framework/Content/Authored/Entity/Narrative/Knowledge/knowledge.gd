extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"knowledge": {
			"facts": {},
			"last_updated_tick": 0,
			"learned_from": {}
		}
	}
