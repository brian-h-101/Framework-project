extends RefCounted

# Example initial schedules data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"schedule": {
			"period_ticks": 24,
			"current_stop_index": 0,
			"last_processed_tick": 0,
			"stops": [
				{
					"start_tick": 0,
					"location_id": "outpost_gate",
					"activity": "guarding",
				},
				{
					"start_tick": 8,
					"location_id": "outpost_bunk",
					"activity": "resting",
				},
				{
					"start_tick": 16,
					"location_id": "outpost_gate",
					"activity": "guarding",
				},
			],
		},
	}
