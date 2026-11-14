extends RefCounted

const GameRuntime = preload(
	"res://Framework/API/Runtime/game_runtime.gd"
)


func register_content(_runtime: GameRuntime) -> void:
	pass


func create_entities(
	_runtime: GameRuntime
) -> Dictionary[StringName, int]:
	return {}
