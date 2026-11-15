# declares which interactions Player may invoke.
extends RefCounted

const Strike = preload(
	"res://Framework/Content/Interaction/strike.gd"
)


static func definitions() -> Array[Dictionary]:
	return [
		Strike.definition(),
	]