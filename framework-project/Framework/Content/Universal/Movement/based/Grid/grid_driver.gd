extends "res://Framework/Content/Universal/Movement/based/Physics2D/physics_2d_driver.gd"

const GridMotion = preload("res://Framework/Content/Universal/Movement/based/Grid/grid_motion.gd")

var _map: Node2D
var _motion: GridMotion


func _init(body: CharacterBody2D, bridge: RefCounted, entity: Node, scale: float, map: Node2D, rules: Dictionary) -> void:
	super(body, bridge, entity, scale)
	_map = map
	_motion = GridMotion.new(rules, scale)


func apply_movement(desired: Dictionary, delta: float) -> String:
	var before := _map.to_local(_body.global_position)
	var after := _motion.advance(before, desired[&"lateral"], desired[&"forward"], delta)
	if before != after:
		_body.global_position = _map.to_global(after)
	return ""


func _offset_to(point: Node2D) -> Vector2:
	return _map.to_local(point.global_position) - _map.to_local(_body.global_position)
