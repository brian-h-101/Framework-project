extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"personal_finance": {
			"accounts": {},
			"debts": [],
			"income_per_day": 0,
			"upkeep_per_day": 0
		}
	}
