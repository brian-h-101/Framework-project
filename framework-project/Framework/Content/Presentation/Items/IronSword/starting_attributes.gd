extends RefCounted

const StartingAttributes = preload(
	"res://Framework/Env/Setup/starting_attributes.gd"
)


static func definition() -> Dictionary:
	return StartingAttributes.define(
		&"iron_sword",
		[
			"Entity/Attributes/Identity/identity.gd",
			"Items/Attributes/Physical/physical.gd",
			"Items/Attributes/Value/value.gd",
			"Items/State/Condition/condition.gd",
		],
		{
			&"identity": {"name": "Iron Sword"},
			&"physical": {
				"weight_kg": 3.0,
				"volume_liters": 1.5,
			},
			&"value": {"amount": 50},
		}
	)
