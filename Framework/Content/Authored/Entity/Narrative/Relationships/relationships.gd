extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"relationships": {
			"records": {}
		}
	}
