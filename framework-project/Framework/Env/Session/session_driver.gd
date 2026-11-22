extends Node

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const WorldBridge = preload("res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd")
const TargetResolver = preload("res://Framework/Content/Universal/Targeting/based/Spatial2D/target_resolver_2d.gd")
const TargetResolver3D = preload("res://Framework/Content/Universal/Targeting/based/Spatial3D/target_resolver_3d.gd")

var _runtime: GameRuntime
var _bridge: WorldBridge
var _active_map: Callable


func _init(runtime: GameRuntime, bridge: WorldBridge = null, active_map: Callable = Callable()) -> void:
	_runtime = runtime
	_bridge = bridge
	_active_map = active_map
	if _bridge != null:
		_bridge.configure_behavior_targeting(_resolve_target)
	process_priority = -100


func _process(delta: float) -> void:
	if _runtime == null:
		set_process(false)
		return

	var result := _runtime.advance_time(delta)
	if not result.ok:
		push_error(result.error)
		set_process(false)
		return
	if _bridge != null:
		result = _runtime.advance_behaviors(delta, _resolve_target)
		if not result["ok"]:
			push_error(result["error"])
			set_process(false)
			return
		result = _runtime.advance_automations(delta, _resolve_target)
		if not result["ok"]:
			push_error(result["error"])
			set_process(false)


func _resolve_target(entity_id: int, mode: StringName) -> Dictionary:
	if _active_map.is_valid() and _active_map.call() is Node3D:
		return TargetResolver3D.resolve_entity(_bridge, entity_id, mode)
	return TargetResolver.resolve_entity(_bridge, entity_id, mode)


func _exit_tree() -> void:
	if _bridge != null:
		_bridge.configure_behavior_targeting(Callable())
	_runtime = null
	_bridge = null
	_active_map = Callable()
