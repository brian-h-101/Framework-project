extends RefCounted

const FragmentComposition = preload(
	"res://Framework/Env/Setup/Composition/fragment_composition.gd"
)
const Health = preload(
	"res://Framework/Content/Gameplay/Authored/Entity/Attributes/Statistics/health.tres"
)
const Speed = preload(
	"res://Framework/Content/Gameplay/Authored/Entity/Attributes/Statistics/speed.tres"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	var result := FragmentComposition.compose_resources([Health, Speed])
	if not result["ok"]:
		push_error(String(result["error"]))
		return {}
	return result["value"]
