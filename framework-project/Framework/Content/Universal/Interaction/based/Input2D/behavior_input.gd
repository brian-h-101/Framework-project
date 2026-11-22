extends Node

const WorldBridge = preload("res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd")
const TargetPoint = preload("res://Framework/Content/Universal/Targeting/based/Spatial2D/target_point_2d.gd")

var _bridge: WorldBridge
var _actor: Node
var _controls: Dictionary[StringName, Dictionary] = {}

func configure_entity(bridge: WorldBridge, actor: Node) -> void:
	_bridge = bridge
	_actor = actor

func configure_controls(controls: Dictionary[StringName, Dictionary]) -> void:
	_controls = controls

func _unhandled_input(event: InputEvent) -> void:
	if _bridge == null or not is_instance_valid(_actor):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_at_pointer(event.position)
		return
	for action in _controls:
		var control: Dictionary = _controls[action]
		if control.has("behavior_event") and event.is_action_pressed(action, false):
			get_viewport().set_input_as_handled()
			print("[behavior] %s: %s" % [control["behavior_event"], _execute_control(control)])
			return

func _select_at_pointer(position: Vector2) -> void:
	var nearest: Node = null
	var distance := 40.0 * 40.0
	# Target markers supply their own canvas transforms, including a following Camera2D.
	for id in _bridge.bound_entity_ids():
		var candidate := _bridge.node_for(id)
		if candidate == _actor:
			continue
		var found := TargetPoint.find_for(candidate)
		if not found["ok"]:
			continue
		var point := found["value"] as Node2D
		if not point.is_inside_tree():
			continue
		var squared := (point.get_global_transform_with_canvas().origin - position).length_squared()
		if squared < distance:
			distance = squared
			nearest = candidate
	_bridge.select_behavior_target(_actor, nearest)

func _exit_tree() -> void:
	_bridge = null
	_actor = null
	_controls = {}

func _execute_control(control: Dictionary) -> Dictionary:
	if _bridge == null or not is_instance_valid(_actor) or not control.has("behavior_event"):
		return {"ok": false, "value": null, "error": "Behavior input has no actor or event configuration."}
	return _bridge.emit_behavior_event(_actor, StringName(control["behavior_event"]))
