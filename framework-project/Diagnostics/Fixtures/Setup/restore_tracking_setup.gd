extends "res://Framework/Env/Setup/Bootstrap/game_setup.gd"

var captured_runtime: GameRuntime
var create_entities_called: bool = false


func register_content(runtime: GameRuntime) -> Dictionary:
	captured_runtime = runtime
	return super.register_content(runtime)


func create_entities(
	runtime: GameRuntime
) -> Dictionary[StringName, int]:
	create_entities_called = true
	return super.create_entities(runtime)