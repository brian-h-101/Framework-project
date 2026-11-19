extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)

var _host := GameHost.new()


func _initialize() -> void:
	call_deferred("_start_session")


func _start_session() -> void:
	var started := _host.start_configured(root)

	if not started.ok:
		push_error(started.error)
		quit(1)
		return

	print("[host] Session started.")


func _finalize() -> void:
	_host.stop()