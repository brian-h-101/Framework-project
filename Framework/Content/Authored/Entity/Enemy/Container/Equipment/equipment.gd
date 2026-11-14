extends RefCounted

# Example initial equipment data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"equipment": {
			"slots": {
				"main_hand": null,
				"off_hand": null,
				"body": null,
			},
			"allowed_slot_types": [
				"hand",
				"body",
			],
			"modifier_ids": [],
		},
	}
