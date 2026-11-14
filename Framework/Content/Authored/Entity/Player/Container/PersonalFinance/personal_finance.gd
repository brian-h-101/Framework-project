extends RefCounted

# Example initial personal finance data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"personal_finance": {
			"accounts": {
				"savings": {
					"currency": "coin",
					"balance": 100,
				},
			},
			"debts": [],
			"income_per_day": 10,
			"upkeep_per_day": 2,
		},
	}
