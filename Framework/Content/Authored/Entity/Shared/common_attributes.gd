extends RefCounted

const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)
const Health = preload(
	"res://Framework/Content/Authored/Entity/Attributes/Statistics/health.gd"
)
const Speed = preload(
	"res://Framework/Content/Authored/Entity/Attributes/Statistics/speed.gd"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	return ContentComposition.combine([
		Health.defaults(),
		Speed.defaults(),
	])
