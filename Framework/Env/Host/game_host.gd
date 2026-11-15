extends RefCounted

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)
const MapCoordinator = preload(
	"res://Framework/Env/Map/map_coordinator.gd"
)
const Controls = preload(
	"res://Framework/Content/Configuration/Input/controls.gd"
)
const InputConfiguration = preload(
	"res://Framework/Env/Input/input_configuration.gd"
)
const Displays = preload(
	"res://Framework/Content/Configuration/Presentation/displays.gd"
)
var entry := GameEntry.new()
var maps: MapCoordinator


func start(map_parent: Node) -> Dictionary:
	if not is_instance_valid(map_parent):
		return {
			"ok": false,
			"value": null,
			"error": "Map parent is invalid.",
		}

	var setup := EnvironmentSetup.new()
	var started := entry.start(setup)
	if not started.ok:
		return started

	var controls := Controls.defaults()
	InputConfiguration.apply(controls)
	var displays := Displays.defaults()

	maps = MapCoordinator.new(
		map_parent,
		entry.world_bridge,
		entry.entity_ids,
		controls,
		displays
	)

	var loaded := maps.load_map(setup.get_initial_map())
	if not loaded.ok:
		stop()
		return loaded

	return started


func stop() -> void:
	if maps != null:
		maps.unload_map()
		maps = null

	entry.stop()