extends SceneTree

const Host = preload("res://Framework/Env/Host/game_host.gd")
const Map = preload("res://Diagnostics/Fixtures/Automation/automation_map.tscn")
var _host := Host.new()


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var result := _host.start(root)
	if result["ok"]:
		result = _host.maps.load_map(Map)
	if not result["ok"]:
		push_error(result["error"])
		_host.stop()
		quit(1)
		return
	# This preview always starts fresh and cannot overwrite the normal save slot.
	root.get_node("SessionInput").set_process_unhandled_input(false)
	root.get_node("SessionInput").set_process_input(false)
	print("[automation-visual] Fresh preview ready. Player automatically strikes the nearest target once per second. Close the window to finish.")


func _finalize() -> void:
	_host.stop()
