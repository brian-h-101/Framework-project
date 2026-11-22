extends "res://Framework/Content/Universal/Movement/based/Contracts/movement_environment_spec.gd"

const PhysicsDriver = preload("res://Framework/Content/Universal/Movement/based/Physics2D/physics_2d_driver.gd")


func environment_id() -> String:
	return "physics_2d"


func body_type() -> String:
	return "CharacterBody2D"


func create_driver(body: Node, _map: Node, bridge: RefCounted, entity: Node) -> Driver:
	var body_2d := body as CharacterBody2D
	return PhysicsDriver.new(body_2d, bridge, entity, units_per_gameplay_unit) if body_2d != null else null
