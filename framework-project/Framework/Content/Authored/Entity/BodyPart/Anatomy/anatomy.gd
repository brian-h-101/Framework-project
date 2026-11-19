extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"anatomy": {
			"body_plan": "",
			"dominant_hand": "",
			"parts": []
		}
	}
