extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"crafting": {
			"known_recipe_ids": [],
			"recipes": {},
			"station_id": ""
		}
	}
