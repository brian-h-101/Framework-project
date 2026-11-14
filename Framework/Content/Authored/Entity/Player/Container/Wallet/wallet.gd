extends RefCounted

# Example initial wallet data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"wallet": {
			"currency": "coin",
			"balance": 25,
		},
	}
