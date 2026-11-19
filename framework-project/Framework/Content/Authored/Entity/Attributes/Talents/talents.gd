extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"talents": {
			"known": [],
			"ranks": {},
			"unspent_points": 0
		}
	}
