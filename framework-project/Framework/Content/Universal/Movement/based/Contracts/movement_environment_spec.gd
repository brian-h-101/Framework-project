extends "res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd"

const Driver = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_environment.gd")

@export var units_per_gameplay_unit: float = 1.0


func environment_id() -> String:
	return ""


func body_type() -> String:
	return ""


func create_driver(_body: Node, _map: Node, _bridge: RefCounted, _entity: Node) -> Driver:
	return null


func to_definition() -> Dictionary:
	return {"kind": environment_id(), "units_per_gameplay_unit": units_per_gameplay_unit}


func validation_error() -> String:
	if environment_id().is_empty() or body_type().is_empty():
		return "Choose a concrete movement environment."
	if not is_finite(units_per_gameplay_unit) or units_per_gameplay_unit <= 0:
		return "The environment scale must be positive and finite."
	return ""
