extends Node

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)

var _runtime: GameRuntime


func _init(runtime: GameRuntime) -> void:
	_runtime = runtime
	process_priority = -100


func _process(delta: float) -> void:
	if _runtime == null:
		set_process(false)
		return

	var result := _runtime.advance_time(delta)
	if not result.ok:
		push_error(result.error)
		set_process(false)


func _exit_tree() -> void:
	_runtime = null