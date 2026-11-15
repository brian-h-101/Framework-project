extends RefCounted

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)
const Attributes = preload(
	"res://Framework/Content/Authored/Entity/Player/Attributes/attributes.gd"
)
const BodyParts = preload(
	"res://Framework/Content/Authored/Entity/Player/BodyPart/body_parts.gd"
)
const Containers = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/containers.gd"
)
const Narrative = preload(
	"res://Framework/Content/Authored/Entity/Player/Narrative/narrative.gd"
)
const State = preload(
	"res://Framework/Content/Authored/Entity/Player/State/state.gd"
)
const StatusEffects = preload(
	"res://Framework/Content/Authored/Entity/Player/StatusEffects/status_effects.gd"
)
const Interactions = preload(
	"res://Framework/Content/Authored/Entity/Player/Interactions/interactions.gd"
)


static func define(game: GameRuntime) -> void:
	var containers := ContentComposition.combine([
		Attributes.defaults(),
		BodyParts.defaults(),
		Containers.defaults(),
		Narrative.defaults(),
		State.defaults(),
		StatusEffects.defaults(),
		Interactions.defaults(),
	])
	game.define_attributes(&"player", containers)
