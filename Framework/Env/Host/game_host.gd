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

	maps = MapCoordinator.new(
		map_parent,
		entry.world_bridge,
		entry.entity_ids
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