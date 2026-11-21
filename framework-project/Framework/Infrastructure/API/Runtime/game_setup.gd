extends RefCounted

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)


func register_executors(_runtime: GameRuntime) -> Dictionary:
	return {"ok": true, "value": true, "error": ""}


func register_content(_runtime: GameRuntime) -> Dictionary:
	return {"ok": true, "value": true, "error": ""}

func create_entities(
	_runtime: GameRuntime
) -> Dictionary[StringName, int]:
	return {}


func get_clock_definition() -> Dictionary:
	return {}
