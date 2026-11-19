extends RefCounted

const HOURS_PER_DAY: float = 24.0

var _seconds_per_day: float
var _total_hours: float


func _init(definition: Dictionary) -> void:
	_seconds_per_day = float(definition["seconds_per_day"])
	_total_hours = float(definition["starting_hour"])


func advance(delta_seconds: float) -> void:
	_total_hours += delta_seconds * HOURS_PER_DAY / _seconds_per_day


func get_hour() -> float:
	return fposmod(_total_hours, HOURS_PER_DAY)


func get_day_number() -> int:
	return int(floor(_total_hours / HOURS_PER_DAY)) + 1


func get_day_fraction() -> float:
	return get_hour() / HOURS_PER_DAY


func snapshot_state() -> Dictionary:
	return {
		"total_hours": _total_hours,
	}


func restore_state(snapshot: Dictionary) -> Dictionary:
	var saved_hours: Variant = snapshot.get("total_hours")
	if typeof(saved_hours) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure(
			"Clock snapshot requires a numeric total_hours value."
		)

	var hours := float(saved_hours)
	if not is_finite(hours) or hours < 0.0:
		return _failure(
			"Clock total_hours must be finite and at least zero."
		)

	_total_hours = hours

	return {
		"ok": true,
		"value": true,
		"error": "",
	}


func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}
