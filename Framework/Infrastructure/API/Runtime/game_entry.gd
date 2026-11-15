extends RefCounted

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const GameSetup = preload(
	"res://Framework/Infrastructure/API/Runtime/game_setup.gd"
)
const RuntimeCore = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)

var runtime: GameRuntime
var entity_ids: Dictionary[StringName, int] = {}
var world_bridge: WorldBridge

func start(setup: GameSetup) -> Dictionary:
	if runtime != null:
		return {
			"ok": false,
			"value": null,
			"error": "Game session has already started.",
		}

	var core := RuntimeCore.new()
	runtime = GameRuntime.new(core)
	setup.register_content(runtime)
	entity_ids = setup.create_entities(runtime)
	world_bridge = WorldBridge.new(core)

	return {"ok": true, "value": true, "error": ""}

func stop() -> void:
	if world_bridge != null:
		world_bridge.close()

	if runtime != null:
		runtime.close()

	entity_ids.clear()
	world_bridge = null
	runtime = null