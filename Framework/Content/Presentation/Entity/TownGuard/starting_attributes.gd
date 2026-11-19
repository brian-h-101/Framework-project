extends RefCounted

const StartingAttributes = preload(
	"res://Framework/Env/Setup/starting_attributes.gd"
)


static func definition() -> Dictionary:
	return StartingAttributes.define(
		&"town_guard",
		[
			"Attributes/Identity/identity.gd",
			"Attributes/Statistics/health.gd",
			"Attributes/Statistics/speed.gd",
			"Interactions/interactions.gd",
		],
		{
			&"identity": {
				"name": "TownGuard"
			}
		}
	)
