extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"schedule": {
			"current_stop_index": 0,
			"last_processed_tick": 0,
			"period_ticks": 0,
			"stops": []
		}
	}
