extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"value": {
			"amount": 0,
			"currency": "coin",
		},
	}
