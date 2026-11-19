extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"ownership": {
			"borrowed_item_keys": [],
			"can_transfer": false,
			"owned_item_keys": []
		}
	}
