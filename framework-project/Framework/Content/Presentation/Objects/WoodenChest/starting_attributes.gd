extends RefCounted

const StartingAttributes = preload(
	"res://Framework/Env/Setup/starting_attributes.gd"
)


static func definition() -> Dictionary:
	return StartingAttributes.define(
		&"wooden_chest",
		[
			"Entity/Attributes/Identity/identity.gd",
			"Entity/Container/inventory.gd",
			"Items/State/Condition/condition.gd",
			"Objects/Attributes/Structure/structure.gd",
			"Objects/State/Access/access.gd",
		],
		{
			&"identity": {"name": "Wooden Chest"},
			&"inventory": {"capacity": 12},
			&"structure": {
				"material": "wood",
				"destructible": true,
			},
			&"access": {"locked": true},
		}
	)
