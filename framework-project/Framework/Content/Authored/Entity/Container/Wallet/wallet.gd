extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"wallet": {
			"balance": 0,
			"currency": ""
		}
	}
