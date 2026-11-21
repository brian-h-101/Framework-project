extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)
const TrackingSetup = preload(
	"res://Diagnostics/Fixtures/Setup/restore_tracking_setup.gd"
)
const MapCoordinator = preload(
	"res://Framework/Env/Map/map_coordinator.gd"
)

var _entry := GameEntry.new()
var _maps: MapCoordinator
var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var started := _entry.start(EnvironmentSetup.new())
	if not started["ok"]:
		push_error(String(started["error"]))
		quit(1)
		return

	var source_runtime := _entry.runtime
	var controls: Dictionary[StringName, Dictionary] = {}
	var map_scene := _make_map()
	_maps = MapCoordinator.new(
		root, _entry.world_bridge, _entry.entity_ids, controls, source_runtime
	)

	var loaded := _maps.load_map(map_scene)
	if not loaded["ok"]:
		push_error(String(loaded["error"]))
		quit(1)
		return

	var player_id: int = _entry.entity_ids[&"player"]
	var guard_id: int = _entry.entity_ids[&"town_guard_01"]

	var player_changed := source_runtime.write_attribute(
		player_id, &"health", ["current"], 42
	)
	var guard_changed := source_runtime.write_attribute(
		guard_id, &"health", ["current"], 35
	)
	var inventory_added := source_runtime.add_container(
		guard_id, &"inventory",
		{"capacity": 6, "items": {"ration": 2}}
	)
	var empty_added := source_runtime.add_container(guard_id, &"empty_pack")

	var prepared: bool = (
		player_changed["ok"]
		and guard_changed["ok"]
		and inventory_added["ok"]
		and empty_added["ok"]
	)
	_expect("Source session prepared", prepared)
	if not prepared:
		quit(1)
		return

	var captured := _entry.snapshot_session()
	if not captured["ok"]:
		push_error(String(captured["error"]))
		quit(1)
		return

	var snapshot: Dictionary = captured["value"]
	var expected: Dictionary = snapshot.duplicate(true)

	_maps.unload_map()
	await process_frame
	_maps = null
	_entry.stop()

	var restore_setup := TrackingSetup.new()
	var restored := _entry.restore_session(restore_setup, snapshot)
	_expect("Session restored", restored["ok"])
	if not restored["ok"]:
		push_error(String(restored["error"]))
		quit(1)
		return

	_expect("Receiving runtime is a new instance", (
		_entry.runtime != source_runtime
		and restore_setup.captured_runtime == _entry.runtime
	))
	_expect("Startup entity spawning was skipped", (
		not restore_setup.create_entities_called
	))
	_expect("Fresh world bridge starts without bindings", (
		_entry.world_bridge != null
		and _entry.world_bridge.bound_entity_ids().is_empty()
	))

	var expected_keys: Array = expected["entities"].keys()
	_expect("Stable keys are rebuilt", (
		_entry.entity_ids.keys() == expected_keys
	))

	var round_trip := _entry.snapshot_session()
	_expect("Complete entity state survives the session round trip", (
		round_trip["ok"] and round_trip["value"] == expected
	))

	snapshot["entities"][&"town_guard_01"]["containers"][&"inventory"]["items"]["ration"] = 99
	snapshot["entities"].erase(&"enemy")

	var after_input_changes := _entry.snapshot_session()
	_expect("Input snapshot changes leave the session unchanged", (
		after_input_changes["ok"]
		and after_input_changes["value"] == expected
	))

	var restored_ids: Dictionary = _entry.entity_ids.duplicate()
	_maps = MapCoordinator.new(
		root, _entry.world_bridge, _entry.entity_ids, controls, _entry.runtime
	)

	var rebound := _maps.load_map(map_scene)
	_expect("Map loads into the restored session", rebound["ok"])
	if not rebound["ok"]:
		push_error(String(rebound["error"]))
		quit(1)
		return

	_expect("Map loading reuses restored identities", (
		_entry.entity_ids == restored_ids
	))

	var restored_player_id: int = _entry.entity_ids[&"player"]
	var restored_guard_id: int = _entry.entity_ids[&"town_guard_01"]
	var player_node := _entry.world_bridge.node_for(restored_player_id)
	var guard_node := _entry.world_bridge.node_for(restored_guard_id)

	_expect("Map nodes bind to the restored entities", (
		player_node != null
		and guard_node != null
		and _entry.world_bridge.entity_for(player_node) == restored_player_id
		and _entry.world_bridge.entity_for(guard_node) == restored_guard_id
	))

	var player_health := _entry.world_bridge.read_attribute(
		player_node, &"health", ["current"]
	)
	var guard_items := _entry.world_bridge.read_attribute(
		guard_node, &"inventory", ["items", "ration"]
	)
	_expect("Player node reads restored health", (
		player_health["ok"] and player_health["value"] == 42
	))
	_expect("Guard node reads acquired inventory", (
		guard_items["ok"] and guard_items["value"] == 2
	))

	_maps.unload_map()
	await process_frame
	_entry.stop()

	print("[session-restore] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _make_map() -> PackedScene:
	var map_root := Node.new()
	map_root.name = &"SessionRestoreMap"

	var definitions: Dictionary[StringName, StringName] = {
		&"player": &"player",
		&"town_guard_01": &"town_guard",
	}
	for entity_key in definitions:
		var entity_node := Node.new()
		entity_node.name = entity_key
		entity_node.set_meta(&"entity_key", entity_key)
		entity_node.set_meta(&"entity_definition", definitions[entity_key])
		map_root.add_child(entity_node)
		entity_node.owner = map_root

	var packed := PackedScene.new()
	var error := packed.pack(map_root)
	map_root.free()

	if error != OK:
		push_error("Could not build diagnostic map: %s" % error_string(error))
		return null

	return packed


func _expect(label: String, condition: bool) -> void:
	print("[session-restore] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	if _maps != null:
		_maps.unload_map()
	_entry.stop()