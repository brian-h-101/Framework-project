extends RefCounted


static func definition() -> Dictionary:
	return {
		"id": &"headless_probe",
		"containers": {
			&"identity": {"name": "Probe"},
		},
	}
