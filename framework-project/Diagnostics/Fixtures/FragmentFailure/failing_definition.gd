extends RefCounted

const FragmentComposition = preload(
	"res://Framework/Env/Setup/Composition/fragment_composition.gd"
)


static func definition() -> Dictionary:
	return FragmentComposition.compose_in(
		"res://Diagnostics/Fixtures/FragmentFailure/Missing"
	)