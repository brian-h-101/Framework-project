extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"structure": {
			"material": "",
			"destructible": false,
		},
	}
