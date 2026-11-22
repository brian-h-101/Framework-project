extends RefCounted

const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")


static func calculate(direction: Dictionary, speed: Variant) -> Dictionary:
	var length_squared := 0.0
	for axis: StringName in Intent.AXES:
		var value: Variant = direction.get(axis)
		if not Intent.is_finite_axis(value) or absf(float(value)) > 1.0:
			return _failure("Movement direction axes must be finite and between -1 and 1.")
		length_squared += float(value) * float(value)

	if not Intent.is_finite_axis(speed) or float(speed) < 0.0:
		return _failure("Movement speed must be numeric, finite and nonnegative.")

	var scale := float(speed) / maxf(1.0, sqrt(length_squared))
	var velocity := {}
	for axis: StringName in Intent.AXES:
		velocity[axis] = direction[axis] * scale
	return {"ok": true, "value": velocity, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
