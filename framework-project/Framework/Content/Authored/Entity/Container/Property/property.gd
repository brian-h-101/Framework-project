extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"property": {
			"owned": [],
			"rented": []
		}
	}
