extends RefCounted


static func sample(
	day_fraction: float,
	sunrise: float,
	sunset: float
) -> Dictionary[StringName, float]:
	var progress := clampf(
		(day_fraction - sunrise) / (sunset - sunrise),
		0.0,
		1.0
	)

	var daylight := 0.0
	if day_fraction >= sunrise and day_fraction < sunset:
		daylight = sin(progress * PI)

	return {&"progress": progress, &"daylight": daylight}
