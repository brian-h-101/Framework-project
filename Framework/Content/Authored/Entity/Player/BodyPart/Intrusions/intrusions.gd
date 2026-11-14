extends RefCounted

# Example initial intrusions data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"intrusions": {
			"installed": [],
			"foreign_objects": [],
		},
	}
