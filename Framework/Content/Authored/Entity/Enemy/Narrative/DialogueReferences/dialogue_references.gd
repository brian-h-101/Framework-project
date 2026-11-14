extends RefCounted

# Example initial dialogue references data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"dialogue_references": {
			"default_dialogue_id": "enemy_warning",
			"known_dialogue_ids": [
				"enemy_warning",
			],
			"last_node_id": "",
		},
	}
