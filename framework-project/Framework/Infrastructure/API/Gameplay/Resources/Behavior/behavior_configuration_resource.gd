extends Resource

@export_enum("manual", "event", "interval") var trigger: String = "event"
@export var event_id: StringName = &"on_attack"
@export_enum("nearest", "selected", "self") var targeting: String = "nearest"
@export var interval_seconds: float = 1.0
@export var cooldown_seconds: float = 1.5

func to_definition() -> Dictionary:
	return {"trigger": trigger, "event_id": event_id, "targeting": targeting,
		"interval_seconds": interval_seconds, "cooldown_seconds": cooldown_seconds}
