extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"intrusions": {
			"foreign_objects": [],
			"installed": []
		}
	}
