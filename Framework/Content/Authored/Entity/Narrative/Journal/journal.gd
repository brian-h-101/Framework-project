extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"journal": {
			"entries": [],
			"pinned_entry_ids": []
		}
	}
