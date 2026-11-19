extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"factions": {
			"memberships": {}
		}
	}
