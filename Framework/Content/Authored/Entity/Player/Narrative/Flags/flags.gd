extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"narrative": {
			"met_guard": false,
			"accepted_quest": false,
			"discovered_cave": false,
		},
	}
