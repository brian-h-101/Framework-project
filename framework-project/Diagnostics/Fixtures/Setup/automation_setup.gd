extends "res://Framework/Env/Setup/Bootstrap/game_setup.gd"


func register_content(runtime: GameRuntime) -> Dictionary:
	var result := super.register_content(runtime)
	if result["ok"]:
		runtime.define_attributes(&"automation_probe", {
			&"health": {"current": 100}, &"strength": {"current": 20},
			&"interactions": {"available": [&"strike"]}})
	return result
