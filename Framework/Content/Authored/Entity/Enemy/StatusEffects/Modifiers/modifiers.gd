extends RefCounted

# Example initial modifiers data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"modifiers": {
			"active": [
				{
					"id": "alert_awareness",
					"source_effect_id": "alert",
					"target_container": "perception",
					"target_attribute": "awareness",
					"operation": "add",
					"value": 5,
				},
			],
		},
	}
