extends RefCounted

const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)
const ActiveEffectsData = preload(
	"res://Framework/Content/Authored/Entity/Player/StatusEffects/ActiveEffects/active_effects.gd"
)
const ModifiersData = preload(
	"res://Framework/Content/Authored/Entity/Player/StatusEffects/Modifiers/modifiers.gd"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	return ContentComposition.combine([
		ActiveEffectsData.defaults(),
		ModifiersData.defaults(),
	])
