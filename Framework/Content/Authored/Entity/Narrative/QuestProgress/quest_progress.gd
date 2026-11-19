extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"quest_progress": {
			"quests": {}
		}
	}
