extends "res://Framework/Env/Setup/game_setup.gd"

const ContentDiscovery = preload(
	"res://Framework/Env/Setup/content_discovery.gd"
)

var captured_runtime: GameRuntime
var create_entities_called: bool = false


func register_content(runtime: GameRuntime) -> Dictionary:
	captured_runtime = runtime

	var registered := super.register_content(runtime)

	if not registered["ok"]:
		return registered

	return ContentDiscovery.definitions_in(
		"res://Diagnostics/Fixtures/DuplicateActions"
	)


func create_entities(
	runtime: GameRuntime
) -> Dictionary[StringName, int]:
	create_entities_called = true
	return super.create_entities(runtime)