extends RefCounted

# Example initial crafting data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"crafting": {
			"known_recipe_ids": [
				"simple_bandage",
			],
			"recipes": {
				"simple_bandage": {
					"ingredients": {
						"cloth": 2,
					},
					"outputs": {
						"bandage": 1,
					},
					"duration_ticks": 2,
				},
			},
			"station_id": "workbench",
		},
	}
