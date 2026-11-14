extends RefCounted

# Example initial intrusions data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"intrusions": {
			"installed": [],
			"foreign_objects": [
				{
					"id": "wood_splinter",
					"body_part": "left_hand",
					"removable": true,
				},
			],
		},
	}
