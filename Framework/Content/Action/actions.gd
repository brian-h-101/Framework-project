# lists reusable interaction definitions.

extends RefCounted

const ChangeHealth = preload(
	"res://Framework/Content/Action/change_health.gd"
)


static func definitions() -> Array[Dictionary]:
	return [
		ChangeHealth.definition(),
	]