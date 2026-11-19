extends RefCounted

const Baseline = preload(
	"res://Diagnostics/Fixtures/entity_starting_baseline.gd"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	return Baseline.category(&"enemy", "State")
