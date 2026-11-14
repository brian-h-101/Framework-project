extends RefCounted

# Example initial supernatural data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"supernatural": {
			"origin": "latent_psychic",
			"traits": [
				"premonition",
			],
			"resource": {
				"id": "focus",
				"current": 10,
				"maximum": 10,
			},
		},
	}
