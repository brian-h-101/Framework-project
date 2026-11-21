extends Node

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const WorldBridge = preload("res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd")
const TargetResolver = preload("res://Framework/Env/Targeting/target_resolver_2d.gd")

var _runtime: GameRuntime
var _bridge: WorldBridge


func _init(runtime: GameRuntime, bridge: WorldBridge = null) -> void:
	_runtime = runtime
	_bridge = bridge
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
		result = _runtime.advance_automations(delta, _resolve_target)
		if not result["ok"]:
			push_error(result["error"])
			set_process(false)


func _resolve_target(entity_id: int, mode: StringName) -> Dictionary:
	var actor := _bridge.node_for(entity_id)
	if not is_instance_valid(actor):
		return {"ok": false, "value": null, "error": "Actor is not represented in the active map."}
	var result := TargetResolver.resolve(_bridge, actor, mode)
	if result["ok"]:
		return {"ok": true, "value": _bridge.entity_for(result["value"]), "error": ""}
	return result


func _exit_tree() -> void:
	_runtime = null
	_bridge = null
