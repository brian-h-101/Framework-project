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

	var core := RuntimeCore.new(setup.get_clock_definition())
	runtime = GameRuntime.new(core)

	var registered := _register_setup(setup)

	if not registered["ok"]:
		stop()
		return registered

	entity_ids = setup.create_entities(runtime)
	world_bridge = WorldBridge.new(core)

	return {"ok": true, "value": true, "error": ""}

func restore_session(
	setup: GameSetup,
	snapshot: Dictionary
) -> Dictionary:
	if runtime != null:
		return {
			"ok": false,
			"value": null,
			"error": "Game session has already started.",
		}

	var saved_entities: Variant = snapshot.get("entities")
	if not saved_entities is Dictionary:
		return {
			"ok": false,
			"value": null,
			"error": "Session snapshot requires an entities dictionary.",
		}

	var saved_clock: Variant = snapshot.get("clock")
	if saved_clock != null and not (saved_clock is Dictionary):
		return {
			"ok": false,
			"value": null,
			"error": "Session snapshot clock must be a dictionary.",
		}

	var core := RuntimeCore.new(setup.get_clock_definition())
	runtime = GameRuntime.new(core)

	var registered := _register_setup(setup)
	if not registered["ok"]:
		stop()
		return registered

	if saved_clock != null:
		var clock_record: Dictionary = saved_clock
		var clock_restored := runtime.restore_time(clock_record)
		if not clock_restored["ok"]:
			stop()
			return clock_restored

	var records: Dictionary = saved_entities
	var restored := runtime.restore_entities(records)
	if not restored["ok"]:
		stop()
		return restored

	entity_ids = restored["value"]
	var automations := runtime.restore_automations(snapshot.get("automations", {}), entity_ids)
	if not automations["ok"]:
		stop()
		return automations
	world_bridge = WorldBridge.new(core)

	return {
		"ok": true,
		"value": true,
		"error": "",
	}

func _register_setup(setup: GameSetup) -> Dictionary:
	var executors := setup.register_executors(runtime)
	if not executors["ok"]:
		return executors
	return setup.register_content(runtime)


func snapshot_session() -> Dictionary:
	if runtime == null:
		return {
			"ok": false,
			"value": null,
			"error": "Game session is not running.",
		}

	var captured := runtime.snapshot_entities(entity_ids)
	if not captured["ok"]:
		return captured

	var captured_clock := runtime.snapshot_time()
	if not captured_clock["ok"]:
		return captured_clock

	var snapshot: Dictionary = {
		"entities": captured["value"],
	}
	var automations := runtime.snapshot_automations(entity_ids)
	if not automations["ok"]:
		return automations
	# Omit empty state to retain the shape of existing entity-only snapshots.
	if not automations["value"].is_empty():
		snapshot["automations"] = automations["value"]

	if captured_clock["value"] != null:
		snapshot["clock"] = captured_clock["value"]

	return {
		"ok": true,
		"value": snapshot,
		"error": "",
	}

func stop() -> void:
	if world_bridge != null:
		world_bridge.close()

	if runtime != null:
		runtime.close()

	entity_ids.clear()
	world_bridge = null
	runtime = null
