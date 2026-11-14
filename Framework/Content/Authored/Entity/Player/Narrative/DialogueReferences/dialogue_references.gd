extends RefCounted

# Example initial dialogue references data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"dialogue_references": {
			"default_dialogue_id": "player_intro",
			"known_dialogue_ids": [
				"player_intro",
			],
			"last_node_id": "",
		},
	}
