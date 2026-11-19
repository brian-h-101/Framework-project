extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"dialogue_references": {
			"default_dialogue_id": "",
			"known_dialogue_ids": [],
			"last_node_id": ""
		}
	}
