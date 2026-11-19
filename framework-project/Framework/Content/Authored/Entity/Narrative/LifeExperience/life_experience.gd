extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"life_experience": {
			"background": "",
			"education": [],
			"employment": [],
			"milestones": []
		}
	}
