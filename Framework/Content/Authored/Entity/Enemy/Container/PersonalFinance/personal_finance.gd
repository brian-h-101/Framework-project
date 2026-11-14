extends RefCounted

# Example initial personal finance data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"personal_finance": {
			"accounts": {
				"savings": {
					"currency": "coin",
					"balance": 0,
				},
			},
			"debts": [],
			"income_per_day": 4,
			"upkeep_per_day": 2,
		},
	}
