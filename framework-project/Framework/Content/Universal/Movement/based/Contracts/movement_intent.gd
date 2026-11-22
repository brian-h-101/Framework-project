extends RefCounted

const AXES := [&"lateral", &"forward", &"vertical"]
const LEGACY_AXES := [&"direction_x", &"direction_y"]


static func axes(lateral: float = 0.0, forward: float = 0.0, vertical: float = 0.0) -> Dictionary:
	return {&"lateral": lateral, &"forward": forward, &"vertical": vertical}


static func has_axes(values: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not values.has(key):
			return false
	return true


static func is_finite_axis(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func valid_axes(values: Dictionary) -> bool:
	for axis in AXES:
		if not is_finite_axis(values.get(axis)):
			return false
	return true
