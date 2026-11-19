extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"equipment": {
			"allowed_slot_types": [],
			"modifier_ids": [],
			"slots": {
				"body": null,
				"main_hand": null,
				"off_hand": null
			}
		}
	}
