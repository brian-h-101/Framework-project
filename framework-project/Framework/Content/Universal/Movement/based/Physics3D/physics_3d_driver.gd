extends "res://Framework/Content/Universal/Movement/based/Contracts/movement_environment.gd"

const Targets = preload("res://Framework/Content/Universal/Targeting/based/Spatial3D/target_resolver_3d.gd")

var _body: CharacterBody3D
var _bridge: RefCounted
var _entity: Node
var _scale: float


func _init(body: CharacterBody3D, bridge: RefCounted, entity: Node, scale: float) -> void:
	_body = body
	_bridge = bridge
	_entity = entity
	_scale = scale
	_body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func observe_target(mode: StringName, _distance_unit: String) -> Dictionary:
	var found := Targets.resolve(_bridge, _entity, mode)
	if not found["ok"]:
		return {}
	var point := Targets.point_for(found["value"])
	if point == null:
		return {}
	var offset := point.global_position - _body.global_position
	var direction := offset.normalized()
	return {
		"intent": {&"lateral": direction.x, &"forward": -direction.z, &"vertical": direction.y},
		"distance": offset.length() / _scale,
	}


func apply_movement(desired: Dictionary, _delta: float) -> String:
	var velocity := Vector3(
		float(desired[&"lateral"]) * _scale,
		float(desired[&"vertical"]) * _scale,
		-float(desired[&"forward"]) * _scale
	)
	if not velocity.is_finite():
		return "Movement produced an invalid 3D velocity."
	_body.velocity = velocity
	_body.move_and_slide()
	return ""


func stop() -> void:
	_body.velocity = Vector3.ZERO
