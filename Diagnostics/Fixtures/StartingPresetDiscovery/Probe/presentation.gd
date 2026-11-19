extends RefCounted


# Discovery must ignore this file even though it exposes definition().
static func definition() -> Dictionary:
	return {"id": &"presentation_should_not_register", "containers": {}}
