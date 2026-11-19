extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"access": {
			"open": false,
			"locked": false,
		},
	}
