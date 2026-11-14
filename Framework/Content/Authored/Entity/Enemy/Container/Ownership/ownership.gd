extends RefCounted

# Example initial ownership data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"ownership": {
			"owned_item_keys": [],
			"borrowed_item_keys": [],
			"can_transfer": true,
		},
	}
