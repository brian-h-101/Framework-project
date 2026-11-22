extends RefCounted

const Configuration = preload("res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd")
const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")
const DIRECTIONS := ["left", "right", "up", "down"]


static func keyboard_intent(actions: Dictionary, read_input: Callable) -> Dictionary:
	var input: Dictionary = read_input.call(actions)
	return Intent.axes(float(input[&"lateral"]), float(input[&"forward"]))


static func keyboard_error(actions: Dictionary) -> String:
	var used := {}
	for direction in DIRECTIONS:
		var action: Variant = actions.get(direction)
		if not Configuration.is_text(action) or String(action).strip_edges().is_empty():
			return "Keyboard movement requires an action for %s." % direction
		if used.has(String(action)):
			return "Keyboard movement requires distinct directional actions."
		used[String(action)] = true
	return ""


static func ai_intent(observe_target: Callable, mode: StringName, distance_unit: String, stopping_distance: float) -> Dictionary:
	var target: Dictionary = observe_target.call(mode, distance_unit)
	if target.is_empty() or float(target["distance"]) <= stopping_distance:
		return Intent.axes()
	return target["intent"]


static func ai_error(targeting: String, distance_unit: String, stopping_distance: float) -> String:
	if targeting not in ["nearest", "selected"]:
		return "AI movement requires nearest or selected targeting."
	if distance_unit not in ["pixels", "gameplay_units"]:
		return "Choose pixels or gameplay units for the stopping distance."
	if not is_finite(stopping_distance) or stopping_distance < 0.0:
		return "AI movement requires a finite, nonnegative stopping distance."
	return ""
