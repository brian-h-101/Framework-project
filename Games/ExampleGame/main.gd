extends SceneTree

const GameEntry = preload(
	"res://Framework/API/Runtime/game_entry.gd"
)
const ExampleGameSetup = preload(
	"res://Games/ExampleGame/game_setup.gd"
)

var _entry := GameEntry.new()


func _initialize() -> void:
	var started := _entry.start(ExampleGameSetup.new())

	if not started.ok:
		push_error(started.error)
		quit(1)
		return

	print("[entry] Session started.")


func _finalize() -> void:
	_entry.stop()