extends "res://Framework/Content/Universal/Movement/based/Contracts/movement_environment.gd"

const Targets = preload("res://Framework/Content/Universal/Targeting/based/Spatial2D/target_resolver_2d.gd")
const TargetPoint = preload("res://Framework/Content/Universal/Targeting/based/Spatial2D/target_point_2d.gd")

var _body: CharacterBody2D
var _bridge: RefCounted
var _entity: Node
var _scale: float


func _init(body: CharacterBody2D, bridge: RefCounted, entity: Node, scale: float) -> void:
	_body = body
	_bridge = bridge
	_entity = entity
	_scale = scale
	_body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func observe_target(mode: StringName, distance_unit: String) -> Dictionary:
	var found := Targets.resolve(_bridge, _entity, mode)
	if not found["ok"]:
		return {}
	var resolved := TargetPoint.find_for(found["value"])
	if not resolved["ok"]:
		return {}
	var point: Node2D = resolved["value"]
	var offset := _offset_to(point)
	var direction := offset.normalized()
	return {
		"intent": {&"lateral": direction.x, &"forward": -direction.y, &"vertical": 0.0},
		"distance": offset.length() if distance_unit == "pixels" else offset.length() / _scale,
	}


func apply_movement(desired: Dictionary, _delta: float) -> String:
	var velocity := Vector2(float(desired[&"lateral"]) * _scale, -float(desired[&"forward"]) * _scale)
	if not velocity.is_finite():
		return "Movement produced an invalid pixel velocity."
	_body.velocity = velocity
	_body.move_and_slide()
	return ""


func stop() -> void:
	_body.velocity = Vector2.ZERO


func _offset_to(point: Node2D) -> Vector2:
	return point.global_position - _body.global_position
