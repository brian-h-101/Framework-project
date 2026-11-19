extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"evidence": {
			"discovered": {},
			"examined_ids": []
		}
	}
