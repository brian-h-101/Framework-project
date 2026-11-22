extends RefCounted

const Spec = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_environment_spec.gd")
const Physics2D = preload("res://Framework/Content/Universal/Movement/based/Physics2D/physics_2d_spec.gd")


static func resolve(explicit: Spec, legacy_grid: Spec, legacy_scale: float) -> Spec:
	if explicit != null:
		return explicit
	var spec := legacy_grid.duplicate() as Spec if legacy_grid != null else Physics2D.new()
	spec.units_per_gameplay_unit = legacy_scale
	return spec
