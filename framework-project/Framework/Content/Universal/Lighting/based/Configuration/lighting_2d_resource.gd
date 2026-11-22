extends "res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd"

const ShadowsResource = preload("res://Framework/Content/Universal/Lighting/based/Configuration/shadows_resource.gd")

@export var ambient_color: Color = Color.WHITE
@export var shadows: ShadowsResource
@export var day_night: Dictionary = {}
@export var point_lights: Array[Dictionary] = []


func to_definition() -> Dictionary:
	return {
		"ambient_color": ambient_color,
		"shadows": shadows.to_definition() if shadows != null else {},
		"day_night": day_night.duplicate(true),
		"point_lights": point_lights.duplicate(true),
	}


func validation_error() -> String:
	if shadows == null:
		return "Lighting requires a shared shadow configuration."
	var shadow_error := shadows.validation_error()
	if not shadow_error.is_empty():
		return shadow_error
	if not day_night.is_empty():
		if not is_number(day_night.get("sunrise")) or not is_number(day_night.get("sunset")):
			return "Day/night requires numeric sunrise and sunset fractions."
		if day_night["sunrise"] < 0.0 or day_night["sunset"] > 1.0 or day_night["sunrise"] >= day_night["sunset"]:
			return "Day/night requires 0 <= sunrise < sunset <= 1."
		if not day_night.get("night_ambient") is Color or not day_night.get("day_ambient") is Color or not day_night.get("sun") is Dictionary:
			return "Day/night requires ambient colors and a sun dictionary."
		var sun: Dictionary = day_night["sun"]
		if not sun.get("color") is Color:
			return "Sun requires a color."
		for field in ["maximum_energy", "sunrise_angle", "sunset_angle"]:
			if not is_number(sun.get(field)):
				return "Sun %s must be finite and numeric." % field
	for light in point_lights:
		if not is_text(light.get("id")) or String(light["id"]).is_empty() or not light.get("position") is Vector2 or not light.get("color") is Color:
			return "Point lights require an ID, 2D position and color."
		if not is_number(light.get("energy")) or light["energy"] < 0.0 or not is_number(light.get("radius")) or light["radius"] <= 0.0:
			return "Point lights require nonnegative energy and a positive radius."
	return ""
