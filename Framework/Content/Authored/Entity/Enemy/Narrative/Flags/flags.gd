extends RefCounted

# Example initial flags data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"narrative": {
			"met_player": false,
			"alarm_raised": false,
			"surrendered": false,
		},
	}
