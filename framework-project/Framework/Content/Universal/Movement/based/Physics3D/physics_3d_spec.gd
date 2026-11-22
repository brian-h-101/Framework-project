extends "res://Framework/Content/Universal/Movement/based/Contracts/movement_environment_spec.gd"

const PhysicsDriver = preload("res://Framework/Content/Universal/Movement/based/Physics3D/physics_3d_driver.gd")


func environment_id() -> String:
	return "physics_3d"


func body_type() -> String:
	return "CharacterBody3D"


func create_driver(body: Node, map: Node, bridge: RefCounted, entity: Node) -> Driver:
	var body_3d := body as CharacterBody3D
	return PhysicsDriver.new(body_3d, bridge, entity, units_per_gameplay_unit) if body_3d != null and map is Node3D else null
